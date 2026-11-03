CREATE TABLE users (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_name VARCHAR(50) NOT NULL,
  password_hash VARCHAR(256) NOT NULL,
  email VARCHAR(100) COLLATE utf8mb4_bin NOT NULL,
  git_info JSON NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  role VARCHAR(20) NOT NULL DEFAULT 'user',
  auth_source VARCHAR(20) NOT NULL DEFAULT 'password',
  preferences VARCHAR(4096) NOT NULL DEFAULT '{}',
  display_name VARCHAR(100) NULL,
  bio TEXT NULL,
  needs_registration BOOLEAN NOT NULL DEFAULT FALSE,
  token_version INT NOT NULL DEFAULT 0,
  unlock_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
  unlock_expires_at DATETIME(6) NULL,
  unlock_used_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_users_user_name (user_name),
  UNIQUE KEY uq_users_email_lower (email),
  UNIQUE KEY uq_users_unlock_hash (unlock_token_hash),
  KEY idx_users_admin (role,is_active),
  CONSTRAINT ck_users_role CHECK (role IN ('admin','user')),
  CONSTRAINT ck_users_version CHECK (token_version >= 0),
  CONSTRAINT ck_users_email CHECK (
    CHAR_LENGTH(email) > 0 AND BINARY email = BINARY LOWER(TRIM(email)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE teams (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  team_name VARCHAR(100) NOT NULL,
  slug VARCHAR(100) NOT NULL,
  description TEXT NULL,
  created_by_user_id INT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_teams_name (team_name),
  UNIQUE KEY uq_teams_slug (slug),
  KEY idx_teams_created_by (created_by_user_id),
  CONSTRAINT fk_team_creator FOREIGN KEY (created_by_user_id) REFERENCES users(id),
  CONSTRAINT ck_team_name CHECK (CHAR_LENGTH(TRIM(team_name)) BETWEEN 2 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE team_members (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  team_id BIGINT NOT NULL,
  user_id INT NOT NULL,
  team_role VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  invited_by_user_id INT NOT NULL,
  joined_at DATETIME(6) NOT NULL,
  removed_at DATETIME(6) NULL,
  removed_by_user_id INT NULL,
  active_user_id INT GENERATED ALWAYS AS
    (CASE WHEN status='active' THEN user_id ELSE NULL END) STORED,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_team_active_user (team_id,active_user_id),
  KEY idx_members_team (team_id,status,joined_at,id),
  KEY idx_members_user (user_id,status,team_id),
  KEY idx_members_inviter (invited_by_user_id,team_id,user_id),
  KEY idx_members_remover (removed_by_user_id),
  CONSTRAINT fk_member_team FOREIGN KEY (team_id) REFERENCES teams(id),
  CONSTRAINT fk_member_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_member_inviter FOREIGN KEY (invited_by_user_id) REFERENCES users(id),
  CONSTRAINT fk_member_remover FOREIGN KEY (removed_by_user_id) REFERENCES users(id),
  CONSTRAINT ck_member_role CHECK (team_role IN ('team_admin','team_member')),
  CONSTRAINT ck_member_status CHECK (status IN ('active','removed')),
  CONSTRAINT ck_member_removed CHECK (
    (status='active' AND removed_at IS NULL AND removed_by_user_id IS NULL) OR
    (status='removed' AND removed_at IS NOT NULL AND removed_by_user_id IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE invitations (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  team_id BIGINT NOT NULL,
  invitee_name VARCHAR(100) NOT NULL,
  invitee_email VARCHAR(100) COLLATE utf8mb4_bin NOT NULL,
  invitee_bio TEXT NULL,
  team_role VARCHAR(20) NOT NULL,
  invited_by_user_id INT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  invite_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  claimed_user_id INT NULL,
  claimed_at DATETIME(6) NULL,
  pending_email VARCHAR(100) COLLATE utf8mb4_bin GENERATED ALWAYS AS
    (CASE WHEN status='pending' THEN invitee_email ELSE NULL END) STORED,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_invitation_hash (invite_token_hash),
  UNIQUE KEY uq_team_pending_email (team_id,pending_email),
  KEY idx_invitation_team_email (team_id,invitee_email,status),
  KEY idx_invitation_inviter (invited_by_user_id,created_at),
  KEY idx_invitation_status (team_id,status,created_at,id),
  KEY idx_invitation_expiry (status,expires_at),
  KEY idx_invitation_claimed (claimed_user_id),
  CONSTRAINT fk_invitation_team FOREIGN KEY (team_id) REFERENCES teams(id),
  CONSTRAINT fk_invitation_inviter FOREIGN KEY (invited_by_user_id) REFERENCES users(id),
  CONSTRAINT fk_invitation_claimed FOREIGN KEY (claimed_user_id) REFERENCES users(id),
  CONSTRAINT ck_invitation_role CHECK (team_role IN ('team_admin','team_member')),
  CONSTRAINT ck_invitation_status CHECK (status IN ('pending','claimed','revoked','expired')),
  CONSTRAINT ck_invitation_email CHECK (
    CHAR_LENGTH(invitee_email) > 0 AND
    BINARY invitee_email = BINARY LOWER(TRIM(invitee_email))),
  CONSTRAINT ck_invitation_claim CHECK (
    (status='claimed' AND claimed_user_id IS NOT NULL AND claimed_at IS NOT NULL) OR
    (status<>'claimed' AND claimed_user_id IS NULL AND claimed_at IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE audit_logs (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  team_id BIGINT NULL,
  actor_user_id INT NULL,
  action VARCHAR(50) NOT NULL,
  target_user_id INT NULL,
  target_email VARCHAR(100) NULL,
  resource_type VARCHAR(50) NULL,
  resource_id BIGINT NULL,
  detail JSON NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  KEY idx_audit_team (team_id,created_at,id),
  KEY idx_audit_actor (actor_user_id,created_at),
  KEY idx_audit_target (target_user_id,created_at),
  CONSTRAINT fk_audit_team FOREIGN KEY (team_id) REFERENCES teams(id),
  CONSTRAINT fk_audit_actor FOREIGN KEY (actor_user_id) REFERENCES users(id),
  CONSTRAINT fk_audit_target FOREIGN KEY (target_user_id) REFERENCES users(id),
  CONSTRAINT ck_audit_actor CHECK (
    actor_user_id IS NOT NULL OR action IN ('login_failed','auth_rate_limited'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE refresh_tokens (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  token_version INT NOT NULL,
  device_id VARCHAR(100) NULL,
  expires_at DATETIME(6) NOT NULL,
  revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_refresh_hash (token_hash),
  KEY idx_refresh_user (user_id,revoked,expires_at),
  CONSTRAINT fk_refresh_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT ck_refresh_version CHECK (token_version >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE system_configs (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  config_key VARCHAR(100) NOT NULL,
  config_value VARCHAR(4096) NOT NULL DEFAULT '{}',
  version INT NOT NULL DEFAULT 1,
  updated_by INT NULL,
  expires_at DATETIME(6) NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  UNIQUE KEY uq_system_config_key (config_key),
  KEY idx_system_config_expiry (expires_at),
  KEY idx_system_config_actor (updated_by),
  CONSTRAINT fk_config_actor FOREIGN KEY (updated_by) REFERENCES users(id),
  CONSTRAINT ck_system_config_json CHECK (JSON_VALID(config_value))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
