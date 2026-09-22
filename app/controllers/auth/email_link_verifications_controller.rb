# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Auth::EmailLinkVerificationsController < ApplicationController
  layout false

  class Ineligible < StandardError
  end

  VERIFICATION_TTL = 15.minutes
  MAX_ATTEMPTS     = 5
  RESEND_INTERVAL  = 60.seconds
  MAX_SENDS        = 3
  PENDING_SSO_TTL  = 30.minutes

  before_action :require_pending_sso!

  def gate
    @email = pending_sso['email']
    @allowed_domains = allowed_domain_list.join(', ')
  end

  def create
    email = params[:hackclub_email].to_s.strip.downcase
    if !email.match?(EmailLinkVerification::HACKCLUB_EMAIL_FORMAT)
      redirect_to auth_link_email_gate_path, flash: { error: __('Please enter a valid @hackclub.com email address.') }
      return
    end

    if !eligible?(email)
      redirect_to auth_link_email_gate_path, flash: { error: ineligible_message }
      return
    end

    if send_throttled?
      redirect_to auth_link_email_gate_path, flash: { error: __('Please wait a moment before requesting another code.') }
      return
    end

    start_verification(email)
    redirect_to auth_link_email_verify_path
  end

  def verify
    if verification_expired?
      reset_verification_session
      redirect_to auth_link_email_gate_path, flash: { error: __('Verification expired — please request a new code.') }
      return
    end
    @hackclub_email = session[:link_email]
  end

  def confirm
    return if confirm_guard_failed?

    provision_user_from_verification
  end

  def resend
    email = session[:link_email]
    if email.blank?
      redirect_to auth_link_email_gate_path, flash: { error: __('Verification expired — please request a new code.') }
      return
    end

    if !eligible?(email)
      reset_verification_session
      redirect_to auth_link_email_gate_path, flash: { error: ineligible_message }
      return
    end

    if send_throttled?
      redirect_to auth_link_email_verify_path, flash: { error: __('Please wait a moment before requesting another code.') }
      return
    end

    start_verification(email)
    redirect_to auth_link_email_verify_path
  end

  private

  def confirm_guard_failed?
    if verification_expired?
      reset_verification_session
      redirect_to auth_link_email_gate_path, flash: { error: __('Verification expired — please request a new code.') }
      return true
    end

    return true if too_many_attempts?
    return true if code_mismatch?

    false
  end

  def too_many_attempts?
    session[:link_email_attempts] = session[:link_email_attempts].to_i + 1
    return false if session[:link_email_attempts] <= MAX_ATTEMPTS

    reset_verification_session
    redirect_to auth_link_email_gate_path, flash: { error: __('Too many incorrect attempts — please request a new code.') }
    true
  end

  def code_mismatch?
    digest = Digest::SHA256.hexdigest(params[:code].to_s.strip)
    return false if ActiveSupport::SecurityUtils.secure_compare(digest, session[:link_email_code_digest].to_s)

    @hackclub_email = session[:link_email]
    flash.now[:error] = __("That code isn't right — check your email and try again.")
    render :verify, status: :unprocessable_content
    true
  end

  def provision_user_from_verification
    hackclub_email = session[:link_email]
    sso = pending_sso

    auth_hash = build_auth_hash(sso, hackclub_email)
    user = nil

    begin
      ActiveRecord::Base.transaction do
        raise Ineligible if !eligible?(hackclub_email)

        user = User.create_from_hash!(auth_hash)
        Authorization.create!(
          user:     user,
          uid:      sso['uid'],
          provider: sso['provider'],
          token:    sso['token'],
          secret:   sso['secret'],
          username: sso['email'],
        )
        EmailLinkVerification.create!(hackclub_email: hackclub_email, user: user)
      end
    rescue Ineligible, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, Exceptions::UnprocessableContent
      user = nil
    end

    reset_verification_session

    if user
      session.delete(:pending_sso)
      current_user_set(user)
      user.update_last_login
      session[:persistent] = true
      session[:authentication_type] = 'omniauth'
      redirect_to '/'
    else
      redirect_to auth_link_email_gate_path, flash: { error: ineligible_message }
    end
  end

  def build_auth_hash(sso, hackclub_email)
    first_name, _, last_name = sso['name'].to_s.rpartition(' ')
    {
      'uid'      => sso['uid'],
      'login'    => sso['uid'],
      'provider' => sso['provider'],
      'info'     => {
        'email'      => hackclub_email,
        'name'       => sso['name'],
        'first_name' => first_name.presence,
        'last_name'  => last_name.presence,
        'image'      => sso['image'],
      },
    }
  end

  def pending_sso
    sso = session[:pending_sso]
    return nil if !sso.is_a?(Hash) || sso['uid'].blank? || sso['email'].blank?
    return nil if Time.current.to_i - sso['at'].to_i > PENDING_SSO_TTL.to_i

    sso
  end

  def require_pending_sso!
    return if pending_sso.present?

    session.delete(:pending_sso)
    reset_verification_session
    redirect_to '/'
  end

  def eligible?(hackclub_email)
    return false if EmailLinkVerification.used?(hackclub_email)
    return false if User.exists?(['lower(email) = ?', hackclub_email.downcase])
    return false if User.exists?(['lower(email) = ?', pending_sso['email'].to_s.strip.downcase])

    true
  end

  def ineligible_message
    __('That email address cannot be used for verification.')
  end

  def send_throttled?
    return true if session[:link_email_sends].to_i >= MAX_SENDS

    last = session[:link_email_last_sent_at].to_i
    last.positive? && Time.current.to_i - last < RESEND_INTERVAL.to_i
  end

  def start_verification(email)
    code = SecureRandom.random_number(100_000..999_999).to_s
    session[:link_email]              = email
    session[:link_email_code_digest]  = Digest::SHA256.hexdigest(code)
    session[:link_email_expires_at]   = VERIFICATION_TTL.from_now.to_i
    session[:link_email_attempts]     = 0
    session[:link_email_sends]        = session[:link_email_sends].to_i + 1
    session[:link_email_last_sent_at] = Time.current.to_i

    send_verification_email(email, code)
  end

  def send_verification_email(email, code)
    body = <<~TEXT
      Your verification code is: #{code}

      Enter this code to link your account. It expires in 15 minutes.

      If you didn't request this, ignore this email.
    TEXT

    channel = Channel.find_by(area: 'Email::Notification', active: true)
    return if channel.blank?

    sender = Setting.get('notification_sender')
    channel.deliver(
      {
        from:         sender,
        to:           email,
        subject:      "#{code} is your verification code",
        body:         body,
        content_type: 'text/plain',
      },
      true
    )
  end

  def verification_expired?
    session[:link_email].blank? ||
      session[:link_email_code_digest].blank? ||
      Time.current.to_i > session[:link_email_expires_at].to_i
  end

  def reset_verification_session
    session.delete(:link_email)
    session.delete(:link_email_code_digest)
    session.delete(:link_email_expires_at)
    session.delete(:link_email_attempts)
    session.delete(:link_email_sends)
    session.delete(:link_email_last_sent_at)
  end

  def allowed_domain_list
    Setting.get('auth_oidc_allowed_email_domains').to_s.split(',').map { |d| d.strip.downcase }.reject(&:empty?)
  end
end
