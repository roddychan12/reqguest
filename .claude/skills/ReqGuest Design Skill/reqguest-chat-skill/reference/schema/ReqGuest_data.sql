-- ReqGuest: Seed data for ReqGuest_structure.sql
-- Two tenants, multiple workflows, users, and sample requests.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================
-- TENANTS
-- =============================================================
INSERT INTO tenants (id, name, slug, status, settings) VALUES
(1, 'Grand Plaza Hotel', 'grand-plaza', 'active', JSON_OBJECT('timezone','Asia/Kolkata','currency','INR')),
(2, 'QuickBite Foods',   'quickbite',   'active', JSON_OBJECT('timezone','Asia/Kolkata','currency','INR'));

-- =============================================================
-- DEPARTMENTS
-- =============================================================
INSERT INTO departments (id, tenant_id, parent_id, name, code, description) VALUES
(1, 1, NULL, 'Housekeeping',    'HK',  'Room services and guest requests'),
(2, 1, NULL, 'Engineering',     'ENG', 'Maintenance and repairs'),
(3, 1, NULL, 'Food & Beverage', 'FNB', 'In-room dining and restaurant'),
(4, 1, NULL, 'Front Office',    'FO',  'Reception and guest relations'),
(5, 2, NULL, 'Kitchen',         'KIT', 'Food preparation'),
(6, 2, NULL, 'Delivery',        'DEL', 'Delivery riders'),
(7, 2, NULL, 'Customer Support','CS',  'Customer service');

-- =============================================================
-- ROLES
-- =============================================================
INSERT INTO roles (id, tenant_id, name, slug, description) VALUES
(1, 1, 'Administrator', 'admin',      'Full access'),
(2, 1, 'Supervisor',    'supervisor', 'Department supervisor'),
(3, 1, 'Staff',         'staff',      'Department staff'),
(4, 2, 'Administrator', 'admin',      'Full access'),
(5, 2, 'Supervisor',    'supervisor', 'Shift supervisor'),
(6, 2, 'Staff',         'staff',      'Kitchen/delivery staff');

-- =============================================================
-- USERS (password_hash is placeholder bcrypt of "password")
-- =============================================================
INSERT INTO users (id, tenant_id, department_id, full_name, email, phone, password_hash, status) VALUES
(1, 1, 4, 'Arjun Sharma',   'arjun@grandplaza.test',  '+911111111111', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(2, 1, 1, 'Priya Menon',    'priya@grandplaza.test',  '+911111111112', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(3, 1, 1, 'Ravi Kumar',     'ravi@grandplaza.test',   '+911111111113', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(4, 1, 2, 'Suresh Nair',    'suresh@grandplaza.test', '+911111111114', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(5, 1, 3, 'Meera Iyer',     'meera@grandplaza.test',  '+911111111115', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(6, 2, 7, 'Deepak Verma',   'deepak@quickbite.test',  '+912222222221', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(7, 2, 5, 'Chef Anita',     'anita@quickbite.test',   '+912222222222', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(8, 2, 6, 'Ramesh Singh',   'ramesh@quickbite.test',  '+912222222223', '$2y$10$abcdefghijklmnopqrstuv', 'active'),
(9, 2, 6, 'Vikram Patel',   'vikram@quickbite.test',  '+912222222224', '$2y$10$abcdefghijklmnopqrstuv', 'active');

-- =============================================================
-- USER ROLES
-- =============================================================
INSERT INTO user_roles (user_id, role_id) VALUES
(1, 1), (2, 2), (3, 3), (4, 2), (5, 3),
(6, 4), (7, 2), -- Wait: role 7 doesn't exist. Fix below.
(8, 6), (9, 6);

-- Correct mapping (remove the bad row above conceptually — keep only valid pairs)
DELETE FROM user_roles WHERE user_id = 7 AND role_id = 2;
INSERT INTO user_roles (user_id, role_id) VALUES (7, 5);

-- =============================================================
-- WORKFLOWS
-- =============================================================
INSERT INTO workflows (id, tenant_id, name, code, description, version, is_active) VALUES
(1, 1, 'Housekeeping Request', 'hk_request',  'Guest housekeeping requests', 1, 1),
(2, 1, 'Engineering Ticket',   'eng_ticket',  'Maintenance and repair tickets', 1, 1),
(3, 2, 'Food Delivery',        'food_delivery','Food order fulfillment', 1, 1);

-- =============================================================
-- WORKFLOW STATUSES
-- =============================================================
-- Workflow 1: Housekeeping (requested -> accepted -> collected -> delivering -> delivered)
INSERT INTO workflow_statuses (id, workflow_id, name, code, is_initial, is_final, sort_order, color) VALUES
(1, 1, 'Requested',  'requested',  1, 0, 1, '#9CA3AF'),
(2, 1, 'Accepted',   'accepted',   0, 0, 2, '#3B82F6'),
(3, 1, 'Collected',  'collected',  0, 0, 3, '#8B5CF6'),
(4, 1, 'Delivering', 'delivering', 0, 0, 4, '#F59E0B'),
(5, 1, 'Delivered',  'delivered',  0, 1, 5, '#10B981'),
(6, 1, 'Cancelled',  'cancelled',  0, 1, 6, '#EF4444'),

-- Workflow 2: Engineering (raised -> assigned -> in-progress -> completed)
(7,  2, 'Raised',      'raised',      1, 0, 1, '#9CA3AF'),
(8,  2, 'Assigned',    'assigned',    0, 0, 2, '#3B82F6'),
(9,  2, 'In Progress', 'in_progress', 0, 0, 3, '#F59E0B'),
(10, 2, 'On Hold',     'on_hold',     0, 0, 4, '#6B7280'),
(11, 2, 'Completed',   'completed',   0, 1, 5, '#10B981'),
(12, 2, 'Cancelled',   'cancelled',   0, 1, 6, '#EF4444'),

-- Workflow 3: Food Delivery (received -> preparing -> ready -> delivering -> delivered)
(13, 3, 'Received',   'received',   1, 0, 1, '#9CA3AF'),
(14, 3, 'Preparing',  'preparing',  0, 0, 2, '#F59E0B'),
(15, 3, 'Ready',      'ready',      0, 0, 3, '#8B5CF6'),
(16, 3, 'Delivering', 'delivering', 0, 0, 4, '#3B82F6'),
(17, 3, 'Delivered',  'delivered',  0, 1, 5, '#10B981'),
(18, 3, 'Cancelled',  'cancelled',  0, 1, 6, '#EF4444');

-- =============================================================
-- WORKFLOW TRANSITIONS
-- =============================================================
INSERT INTO workflow_transitions (workflow_id, from_status_id, to_status_id, name) VALUES
-- Housekeeping
(1, 1, 2, 'Accept'),
(1, 1, 6, 'Cancel'),
(1, 2, 3, 'Collect'),
(1, 3, 4, 'Start Delivery'),
(1, 4, 5, 'Mark Delivered'),
(1, 2, 6, 'Cancel'),
-- Engineering
(2, 7,  8,  'Assign'),
(2, 8,  9,  'Start Work'),
(2, 9,  10, 'Put On Hold'),
(2, 10, 9,  'Resume'),
(2, 9,  11, 'Complete'),
(2, 7,  12, 'Cancel'),
-- Food Delivery
(3, 13, 14, 'Start Preparing'),
(3, 14, 15, 'Mark Ready'),
(3, 15, 16, 'Dispatch'),
(3, 16, 17, 'Mark Delivered'),
(3, 13, 18, 'Cancel'),
(3, 14, 18, 'Cancel');

-- =============================================================
-- REQUEST TYPES
-- =============================================================
INSERT INTO request_types (id, tenant_id, department_id, workflow_id, name, code, description, assignment_mode, is_active) VALUES
(1, 1, 1, 1, 'Pillow Request',    'pillow_req',  'Extra pillow/linen request', 'auto',       1),
(2, 1, 1, 1, 'Towel Request',     'towel_req',   'Extra towels',               'auto',       1),
(3, 1, 2, 2, 'AC Repair',         'ac_repair',   'Air conditioner issues',     'supervisor', 1),
(4, 1, 2, 2, 'Plumbing Issue',    'plumbing',    'Plumbing and water issues',  'supervisor', 1),
(5, 2, 5, 3, 'Food Order',        'food_order',  'Standard food delivery',     'auto',       1);

-- =============================================================
-- REQUESTS
-- =============================================================
INSERT INTO requests (id, tenant_id, request_type_id, workflow_id, current_status_id, reference_no, title, description, priority, created_by, requester_name, requester_contact, department_id, assigned_user_id, assigned_dept_id, created_at) VALUES
(1, 1, 1, 1, 5,  'HK-2026-0001', 'Extra pillows for Room 402',     'Guest requested 2 extra pillows',              'normal', 1, 'Room 402', '+919000000001', 1, 3, 1, '2026-04-08 09:00:00'),
(2, 1, 2, 1, 3,  'HK-2026-0002', 'Towels for Room 210',            'Fresh towels needed',                          'normal', 1, 'Room 210', '+919000000002', 1, 2, 1, '2026-04-09 08:15:00'),
(3, 1, 3, 2, 9,  'ENG-2026-0001','AC not cooling in Room 515',     'AC blowing warm air',                          'high',   1, 'Room 515', '+919000000003', 2, 4, 2, '2026-04-09 07:30:00'),
(4, 1, 4, 2, 8,  'ENG-2026-0002','Bathroom tap leaking Room 301',  'Continuous dripping from sink tap',            'normal', 1, 'Room 301', '+919000000004', 2, 4, 2, '2026-04-09 10:00:00'),
(5, 2, 5, 3, 17, 'ORD-2026-0001','Order #1001 - Veg Thali x2',     '2 Veg Thali, 1 Lassi',                         'normal', 6, 'Anil Roy', '+919000000010', 5, 8, 6, '2026-04-09 12:00:00'),
(6, 2, 5, 3, 16, 'ORD-2026-0002','Order #1002 - Chicken Biryani',  '1 Chicken Biryani, 1 Coke',                    'high',   6, 'Sneha K',  '+919000000011', 5, 9, 6, '2026-04-09 12:30:00'),
(7, 2, 5, 3, 14, 'ORD-2026-0003','Order #1003 - Paneer Tikka',     '1 Paneer Tikka, 2 Naan',                       'normal', 6, 'Raj M',    '+919000000012', 5, NULL, 5, '2026-04-09 13:00:00');

-- =============================================================
-- REQUEST ASSIGNMENTS (history)
-- =============================================================
INSERT INTO request_assignments (request_id, assigned_to_user, assigned_to_dept, assigned_by, assignment_type, assigned_at, note) VALUES
(1, 3, 1, 2, 'supervisor', '2026-04-08 09:05:00', 'Assigned to Ravi'),
(2, 2, 1, 1, 'auto',       '2026-04-09 08:16:00', 'Auto assigned to supervisor'),
(3, 4, 2, 1, 'supervisor', '2026-04-09 07:45:00', 'Urgent AC case'),
(4, 4, 2, 1, 'supervisor', '2026-04-09 10:05:00', NULL),
(5, 8, 6, 7, 'auto',       '2026-04-09 12:10:00', 'Auto assigned to rider'),
(6, 9, 6, 7, 'auto',       '2026-04-09 12:40:00', 'Auto assigned to rider');

-- =============================================================
-- REQUEST STATUS HISTORY
-- =============================================================
INSERT INTO request_status_history (request_id, from_status_id, to_status_id, changed_by, note, changed_at) VALUES
-- Request 1: HK pillow, fully delivered
(1, NULL, 1, 1, 'Request created',   '2026-04-08 09:00:00'),
(1, 1,    2, 2, 'Accepted',           '2026-04-08 09:05:00'),
(1, 2,    3, 3, 'Linen collected',    '2026-04-08 09:10:00'),
(1, 3,    4, 3, 'On the way',         '2026-04-08 09:12:00'),
(1, 4,    5, 3, 'Delivered to guest', '2026-04-08 09:18:00'),
-- Request 2: HK towel, at collected
(2, NULL, 1, 1, 'Request created', '2026-04-09 08:15:00'),
(2, 1,    2, 2, 'Accepted',         '2026-04-09 08:20:00'),
(2, 2,    3, 2, 'Towels collected', '2026-04-09 08:25:00'),
-- Request 3: Engineering AC, in progress
(3, NULL, 7, 1, 'Ticket raised', '2026-04-09 07:30:00'),
(3, 7,    8, 1, 'Assigned to Suresh', '2026-04-09 07:45:00'),
(3, 8,    9, 4, 'Started work',  '2026-04-09 08:00:00'),
-- Request 4: Plumbing, assigned
(4, NULL, 7, 1, 'Ticket raised', '2026-04-09 10:00:00'),
(4, 7,    8, 1, 'Assigned',      '2026-04-09 10:05:00'),
-- Request 5: Food order delivered
(5, NULL, 13, 6, 'Order received',  '2026-04-09 12:00:00'),
(5, 13,   14, 7, 'Preparing',       '2026-04-09 12:05:00'),
(5, 14,   15, 7, 'Ready for pickup','2026-04-09 12:20:00'),
(5, 15,   16, 8, 'Dispatched',      '2026-04-09 12:22:00'),
(5, 16,   17, 8, 'Delivered',       '2026-04-09 12:45:00'),
-- Request 6: Food order delivering
(6, NULL, 13, 6, 'Order received', '2026-04-09 12:30:00'),
(6, 13,   14, 7, 'Preparing',      '2026-04-09 12:32:00'),
(6, 14,   15, 7, 'Ready',          '2026-04-09 12:50:00'),
(6, 15,   16, 9, 'Out for delivery','2026-04-09 12:55:00'),
-- Request 7: Food order preparing
(7, NULL, 13, 6, 'Order received', '2026-04-09 13:00:00'),
(7, 13,   14, 7, 'Preparing',      '2026-04-09 13:02:00');

-- =============================================================
-- REQUEST AUDIT LOGS
-- =============================================================
INSERT INTO request_audit_logs (tenant_id, request_id, user_id, action, old_values, new_values, ip_address) VALUES
(1, 1, 1, 'request.created',  NULL, JSON_OBJECT('status','requested'), '10.0.0.1'),
(1, 1, 3, 'request.completed',JSON_OBJECT('status','delivering'), JSON_OBJECT('status','delivered'), '10.0.0.3'),
(1, 3, 1, 'request.created',  NULL, JSON_OBJECT('priority','high'), '10.0.0.1'),
(2, 5, 6, 'request.created',  NULL, JSON_OBJECT('status','received'), '10.0.1.1'),
(2, 5, 8, 'request.completed',JSON_OBJECT('status','delivering'), JSON_OBJECT('status','delivered'), '10.0.1.8');

-- =============================================================
-- REQUEST COMMENTS
-- =============================================================
INSERT INTO request_comments (request_id, user_id, body, is_internal) VALUES
(1, 3, 'Delivered 2 extra pillows to guest.', 0),
(3, 4, 'Compressor seems faulty, may need replacement.', 1),
(3, 4, 'Temporary fix applied, cooling restored.', 0),
(5, 8, 'Delivered on time, guest happy.', 0),
(6, 9, 'Traffic heavy on main road.', 1);

-- =============================================================
-- REQUEST ATTACHMENTS
-- =============================================================
INSERT INTO request_attachments (request_id, uploaded_by, file_name, file_path, mime_type, file_size) VALUES
(3, 4, 'ac_unit_photo.jpg', '/uploads/2026/04/ac_unit_photo.jpg', 'image/jpeg', 245678),
(4, 4, 'leak_video.mp4',    '/uploads/2026/04/leak_video.mp4',    'video/mp4',  1548200);

SET FOREIGN_KEY_CHECKS = 1;