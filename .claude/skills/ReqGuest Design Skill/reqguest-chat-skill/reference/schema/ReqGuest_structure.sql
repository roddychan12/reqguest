-- ReqGuest: Multi-tenant dynamic workflow / request management schema
-- Database: MySQL 8+ (InnoDB, utf8mb4)

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================
-- 1. TENANTS
-- =============================================================
CREATE TABLE tenants (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name            VARCHAR(150) NOT NULL,
    slug            VARCHAR(100) NOT NULL,
    status          ENUM('active','inactive','suspended') NOT NULL DEFAULT 'active',
    settings        JSON NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_tenants_slug (slug)
) ENGINE=InnoDB;

-- =============================================================
-- 2. DEPARTMENTS (per tenant)
-- =============================================================
CREATE TABLE departments (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id       BIGINT UNSIGNED NOT NULL,
    parent_id       BIGINT UNSIGNED NULL,
    name            VARCHAR(150) NOT NULL,
    code            VARCHAR(50) NULL,
    description     VARCHAR(500) NULL,
    is_active       TINYINT(1) NOT NULL DEFAULT 1,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_departments_tenant_code (tenant_id, code),
    KEY idx_departments_tenant (tenant_id),
    KEY idx_departments_parent (parent_id),
    CONSTRAINT fk_departments_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_departments_parent FOREIGN KEY (parent_id) REFERENCES departments(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 3. ROLES (per tenant, configurable)
-- =============================================================
CREATE TABLE roles (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id       BIGINT UNSIGNED NOT NULL,
    name            VARCHAR(100) NOT NULL,
    slug            VARCHAR(100) NOT NULL,
    description     VARCHAR(500) NULL,
    permissions     JSON NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_roles_tenant_slug (tenant_id, slug),
    CONSTRAINT fk_roles_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =============================================================
-- 4. USERS (per tenant)
-- =============================================================
CREATE TABLE users (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id       BIGINT UNSIGNED NOT NULL,
    department_id   BIGINT UNSIGNED NULL,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(190) NOT NULL,
    phone           VARCHAR(30) NULL,
    password_hash   VARCHAR(255) NOT NULL,
    status          ENUM('active','inactive','suspended') NOT NULL DEFAULT 'active',
    last_login_at   DATETIME NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_tenant_email (tenant_id, email),
    KEY idx_users_tenant (tenant_id),
    KEY idx_users_department (department_id),
    CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_users_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 5. USER <-> ROLE (many-to-many)
-- =============================================================
CREATE TABLE user_roles (
    user_id         BIGINT UNSIGNED NOT NULL,
    role_id         BIGINT UNSIGNED NOT NULL,
    assigned_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, role_id),
    KEY idx_user_roles_role (role_id),
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =============================================================
-- 6. REQUEST TYPES (e.g., Food Delivery, AC Repair, Pillow Request)
-- =============================================================
CREATE TABLE request_types (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id           BIGINT UNSIGNED NOT NULL,
    department_id       BIGINT UNSIGNED NULL,
    workflow_id         BIGINT UNSIGNED NULL,
    name                VARCHAR(150) NOT NULL,
    code                VARCHAR(50) NOT NULL,
    description         VARCHAR(500) NULL,
    assignment_mode     ENUM('auto','supervisor','pick','manual') NOT NULL DEFAULT 'manual',
    is_active           TINYINT(1) NOT NULL DEFAULT 1,
    metadata_schema     JSON NULL,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_request_types_tenant_code (tenant_id, code),
    KEY idx_request_types_tenant (tenant_id),
    KEY idx_request_types_department (department_id),
    KEY idx_request_types_workflow (workflow_id),
    CONSTRAINT fk_request_types_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_request_types_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 7. WORKFLOW DEFINITIONS
-- =============================================================
CREATE TABLE workflows (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id       BIGINT UNSIGNED NOT NULL,
    name            VARCHAR(150) NOT NULL,
    code            VARCHAR(50) NOT NULL,
    description     VARCHAR(500) NULL,
    version         INT UNSIGNED NOT NULL DEFAULT 1,
    is_active       TINYINT(1) NOT NULL DEFAULT 1,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_workflows_tenant_code_version (tenant_id, code, version),
    CONSTRAINT fk_workflows_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB;

ALTER TABLE request_types
    ADD CONSTRAINT fk_request_types_workflow FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE SET NULL;

-- =============================================================
-- 8. WORKFLOW STATUSES (nodes)
-- =============================================================
CREATE TABLE workflow_statuses (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    workflow_id     BIGINT UNSIGNED NOT NULL,
    name            VARCHAR(100) NOT NULL,
    code            VARCHAR(50) NOT NULL,
    description     VARCHAR(500) NULL,
    is_initial      TINYINT(1) NOT NULL DEFAULT 0,
    is_final        TINYINT(1) NOT NULL DEFAULT 0,
    sort_order      INT NOT NULL DEFAULT 0,
    color           VARCHAR(20) NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_workflow_statuses_workflow_code (workflow_id, code),
    KEY idx_workflow_statuses_workflow (workflow_id),
    CONSTRAINT fk_workflow_statuses_workflow FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =============================================================
-- 9. STATUS TRANSITIONS (edges)
-- =============================================================
CREATE TABLE workflow_transitions (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    workflow_id         BIGINT UNSIGNED NOT NULL,
    from_status_id      BIGINT UNSIGNED NOT NULL,
    to_status_id        BIGINT UNSIGNED NOT NULL,
    name                VARCHAR(100) NOT NULL,
    allowed_role_id     BIGINT UNSIGNED NULL,
    conditions          JSON NULL,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_workflow_transitions (workflow_id, from_status_id, to_status_id, name),
    KEY idx_transitions_from (from_status_id),
    KEY idx_transitions_to (to_status_id),
    CONSTRAINT fk_transitions_workflow FOREIGN KEY (workflow_id) REFERENCES workflows(id) ON DELETE CASCADE,
    CONSTRAINT fk_transitions_from FOREIGN KEY (from_status_id) REFERENCES workflow_statuses(id) ON DELETE CASCADE,
    CONSTRAINT fk_transitions_to FOREIGN KEY (to_status_id) REFERENCES workflow_statuses(id) ON DELETE CASCADE,
    CONSTRAINT fk_transitions_role FOREIGN KEY (allowed_role_id) REFERENCES roles(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 10. REQUESTS (the actual work items)
-- =============================================================
CREATE TABLE requests (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id           BIGINT UNSIGNED NOT NULL,
    request_type_id     BIGINT UNSIGNED NOT NULL,
    workflow_id         BIGINT UNSIGNED NOT NULL,
    current_status_id   BIGINT UNSIGNED NOT NULL,
    reference_no        VARCHAR(50) NOT NULL,
    title               VARCHAR(255) NOT NULL,
    description         TEXT NULL,
    priority            ENUM('low','normal','high','urgent') NOT NULL DEFAULT 'normal',
    created_by          BIGINT UNSIGNED NULL,
    requester_name      VARCHAR(150) NULL,
    requester_contact   VARCHAR(150) NULL,
    department_id       BIGINT UNSIGNED NULL,
    assigned_user_id    BIGINT UNSIGNED NULL,
    assigned_dept_id    BIGINT UNSIGNED NULL,
    due_at              DATETIME NULL,
    closed_at           DATETIME NULL,
    metadata            JSON NULL,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_requests_tenant_ref (tenant_id, reference_no),
    KEY idx_requests_tenant_status (tenant_id, current_status_id),
    KEY idx_requests_type (request_type_id),
    KEY idx_requests_workflow (workflow_id),
    KEY idx_requests_assigned_user (assigned_user_id),
    KEY idx_requests_assigned_dept (assigned_dept_id),
    KEY idx_requests_created_at (created_at),
    CONSTRAINT fk_requests_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_requests_type FOREIGN KEY (request_type_id) REFERENCES request_types(id),
    CONSTRAINT fk_requests_workflow FOREIGN KEY (workflow_id) REFERENCES workflows(id),
    CONSTRAINT fk_requests_status FOREIGN KEY (current_status_id) REFERENCES workflow_statuses(id),
    CONSTRAINT fk_requests_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_requests_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL,
    CONSTRAINT fk_requests_assigned_user FOREIGN KEY (assigned_user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_requests_assigned_dept FOREIGN KEY (assigned_dept_id) REFERENCES departments(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 11. REQUEST ASSIGNMENTS (history of assignments)
-- =============================================================
CREATE TABLE request_assignments (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    request_id          BIGINT UNSIGNED NOT NULL,
    assigned_to_user    BIGINT UNSIGNED NULL,
    assigned_to_dept    BIGINT UNSIGNED NULL,
    assigned_by         BIGINT UNSIGNED NULL,
    assignment_type     ENUM('auto','supervisor','pick','manual') NOT NULL,
    assigned_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    unassigned_at       DATETIME NULL,
    note                VARCHAR(500) NULL,
    PRIMARY KEY (id),
    KEY idx_assignments_request (request_id),
    KEY idx_assignments_user (assigned_to_user),
    KEY idx_assignments_dept (assigned_to_dept),
    CONSTRAINT fk_assignments_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_assignments_user FOREIGN KEY (assigned_to_user) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_assignments_dept FOREIGN KEY (assigned_to_dept) REFERENCES departments(id) ON DELETE SET NULL,
    CONSTRAINT fk_assignments_by FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 12. REQUEST STATUS HISTORY (workflow audit trail)
-- =============================================================
CREATE TABLE request_status_history (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    request_id          BIGINT UNSIGNED NOT NULL,
    from_status_id      BIGINT UNSIGNED NULL,
    to_status_id        BIGINT UNSIGNED NOT NULL,
    transition_id       BIGINT UNSIGNED NULL,
    changed_by          BIGINT UNSIGNED NULL,
    note                VARCHAR(1000) NULL,
    changed_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_status_history_request (request_id),
    KEY idx_status_history_changed_at (changed_at),
    CONSTRAINT fk_status_history_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_status_history_from FOREIGN KEY (from_status_id) REFERENCES workflow_statuses(id) ON DELETE SET NULL,
    CONSTRAINT fk_status_history_to FOREIGN KEY (to_status_id) REFERENCES workflow_statuses(id),
    CONSTRAINT fk_status_history_transition FOREIGN KEY (transition_id) REFERENCES workflow_transitions(id) ON DELETE SET NULL,
    CONSTRAINT fk_status_history_user FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 13. REQUEST AUDIT LOG (generic changes)
-- =============================================================
CREATE TABLE request_audit_logs (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tenant_id           BIGINT UNSIGNED NOT NULL,
    request_id          BIGINT UNSIGNED NOT NULL,
    user_id             BIGINT UNSIGNED NULL,
    action              VARCHAR(100) NOT NULL,
    old_values          JSON NULL,
    new_values          JSON NULL,
    ip_address          VARCHAR(45) NULL,
    user_agent          VARCHAR(255) NULL,
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_audit_tenant (tenant_id),
    KEY idx_audit_request (request_id),
    KEY idx_audit_created_at (created_at),
    CONSTRAINT fk_audit_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_audit_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 14. REQUEST COMMENTS / NOTES
-- =============================================================
CREATE TABLE request_comments (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    request_id      BIGINT UNSIGNED NOT NULL,
    user_id         BIGINT UNSIGNED NULL,
    body            TEXT NOT NULL,
    is_internal     TINYINT(1) NOT NULL DEFAULT 0,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_comments_request (request_id),
    CONSTRAINT fk_comments_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- =============================================================
-- 15. REQUEST ATTACHMENTS
-- =============================================================
CREATE TABLE request_attachments (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    request_id      BIGINT UNSIGNED NOT NULL,
    uploaded_by     BIGINT UNSIGNED NULL,
    file_name       VARCHAR(255) NOT NULL,
    file_path       VARCHAR(500) NOT NULL,
    mime_type       VARCHAR(100) NULL,
    file_size       BIGINT UNSIGNED NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_attachments_request (request_id),
    CONSTRAINT fk_attachments_request FOREIGN KEY (request_id) REFERENCES requests(id) ON DELETE CASCADE,
    CONSTRAINT fk_attachments_user FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS = 1;
