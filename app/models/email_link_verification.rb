# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class EmailLinkVerification < ApplicationModel
  HACKCLUB_EMAIL_FORMAT = %r{\A[^@\s]+@hackclub\.com\z}i

  belongs_to :user

  before_validation :normalize_hackclub_email

  validates :hackclub_email, presence:   true,
                             format:     { with: HACKCLUB_EMAIL_FORMAT },
                             uniqueness: { case_sensitive: false }

  def self.used?(email)
    exists?(['lower(hackclub_email) = ?', email.to_s.strip.downcase])
  end

  private

  def normalize_hackclub_email
    self.hackclub_email = hackclub_email.to_s.strip.downcase
  end
end
