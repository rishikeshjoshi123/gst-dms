\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,confirmation_token,recovery_token,email_change_token_new,email_change,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','a0010000-0000-0000-0000-000000000007','authenticated','authenticated','suspend-owner-target@acceptance.test',crypt('CaseChain-local-only-2026!',gen_salt('bf')),now(),'','','','','{"provider":"email","providers":["email"]}','{"full_name":"Owner Suspension Target"}',now(),now()),
('00000000-0000-0000-0000-000000000000','a0010000-0000-0000-0000-000000000008','authenticated','authenticated','suspend-admin-target@acceptance.test',crypt('CaseChain-local-only-2026!',gen_salt('bf')),now(),'','','','','{"provider":"email","providers":["email"]}','{"full_name":"Admin Suspension Target"}',now(),now()),
('00000000-0000-0000-0000-000000000000','a0010000-0000-0000-0000-000000000009','authenticated','authenticated','suspension-viewer@acceptance.test',crypt('CaseChain-local-only-2026!',gen_salt('bf')),now(),'','','','','{"provider":"email","providers":["email"]}','{"full_name":"Suspension Viewer"}',now(),now()),
('00000000-0000-0000-0000-000000000000','a0010000-0000-0000-0000-00000000000a','authenticated','authenticated','suspend-mobile-target@acceptance.test',crypt('CaseChain-local-only-2026!',gen_salt('bf')),now(),'','','','','{"provider":"email","providers":["email"]}','{"full_name":"Mobile Suspension Target"}',now(),now());
INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,id,created_at,updated_at,last_sign_in_at) VALUES
('suspend-owner-target@acceptance.test','a0010000-0000-0000-0000-000000000007','{"sub":"a0010000-0000-0000-0000-000000000007","email":"suspend-owner-target@acceptance.test","email_verified":true}','email','a0010000-0000-0000-0000-000000000007',now(),now(),now()),
('suspend-admin-target@acceptance.test','a0010000-0000-0000-0000-000000000008','{"sub":"a0010000-0000-0000-0000-000000000008","email":"suspend-admin-target@acceptance.test","email_verified":true}','email','a0010000-0000-0000-0000-000000000008',now(),now(),now()),
('suspension-viewer@acceptance.test','a0010000-0000-0000-0000-000000000009','{"sub":"a0010000-0000-0000-0000-000000000009","email":"suspension-viewer@acceptance.test","email_verified":true}','email','a0010000-0000-0000-0000-000000000009',now(),now(),now()),
('suspend-mobile-target@acceptance.test','a0010000-0000-0000-0000-00000000000a','{"sub":"a0010000-0000-0000-0000-00000000000a","email":"suspend-mobile-target@acceptance.test","email_verified":true}','email','a0010000-0000-0000-0000-00000000000a',now(),now(),now());
INSERT INTO public.org_members(org_id,user_id,role) VALUES
('b0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000007','associate'),
('b0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000008','viewer'),
('b0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000009','viewer'),
('b0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-00000000000a','associate');
INSERT INTO public.user_profiles(user_id,display_name,professional_title) VALUES
('a0010000-0000-0000-0000-000000000007','Owner Suspension Target','Associate'),
('a0010000-0000-0000-0000-000000000008','Admin Suspension Target','Observer'),
('a0010000-0000-0000-0000-000000000009','Suspension Viewer','Observer'),
('a0010000-0000-0000-0000-00000000000a','Mobile Suspension Target','Associate')
ON CONFLICT (user_id) DO UPDATE SET display_name=EXCLUDED.display_name,professional_title=EXCLUDED.professional_title;
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,assignee_user_id,status,priority,lifecycle_state,status_changed_by) VALUES
('16100000-0000-4000-8000-000000000031','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001','Owner browser suspension Task','case_note','16110000-0000-4000-8000-000000000031','Owner browser suspension Task','a0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000007','open','normal','active','a0010000-0000-0000-0000-000000000001'),
('16100000-0000-4000-8000-000000000032','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001','Mobile browser suspension Task','case_note','16110000-0000-4000-8000-000000000032','Mobile browser suspension Task','a0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-00000000000a','in_progress','normal','active','a0010000-0000-0000-0000-000000000001');
