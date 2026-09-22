# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CreateEmailLinkVerifications < ActiveRecord::Migration[8.0]
  def change
    create_table :email_link_verifications, id: :integer do |t|
      t.string     :hackclub_email, null: false
      t.references :user,           null: false, type: :integer, foreign_key: true
      t.timestamps limit: 3, null: false
    end

    add_index :email_link_verifications, 'lower(hackclub_email)', unique: true, name: 'index_email_link_verifications_on_lower_hackclub_email'

    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Allowed email domains for OIDC provisioning',
      name:        'auth_oidc_allowed_email_domains',
      area:        'Security::ThirdPartyAuthentication',
      description: 'Comma-separated list of email domains allowed to auto-provision via OIDC (e.g. "hackclub.com"). Users with other email domains will be asked to verify an allowed-domain email. Leave empty to allow all domains.',
      options:     {
        form: [
          {
            display: '',
            null:    true,
            name:    'auth_oidc_allowed_email_domains',
            tag:     'input',
          },
        ],
      },
      preferences: {
        permission: ['admin.security'],
        prio:       21,
      },
      state:       '',
      frontend:    false
    )
  end
end
