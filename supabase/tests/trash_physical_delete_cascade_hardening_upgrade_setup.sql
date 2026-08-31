-- Existing legal rows must remain valid when 00093 replaces legacy FK actions.
INSERT INTO auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) VALUES(
  '00000000-0000-0000-0000-000000000000',
  '93100000-0000-0000-0000-000000000001',
  'authenticated','authenticated','physical-delete-upgrade@test.invalid','x',now(),
  '{}','{}',now(),now()
);

INSERT INTO public.organisations(id,name,created_by)
VALUES('93000000-0000-0000-0000-000000000001','Physical delete upgrade fixture','93100000-0000-0000-0000-000000000001');
INSERT INTO public.clients(id,org_id,name)
VALUES('93200000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','Upgrade client');
INSERT INTO public.matters(id,org_id,client_id,title,matter_code)
VALUES('93300000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','93200000-0000-0000-0000-000000000001','Upgrade matter','PURGE-UPGRADE-01');
INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,display_title)
VALUES('93400000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','93300000-0000-0000-0000-000000000001','fixture/upgrade.pdf','93100000-0000-0000-0000-000000000001','Upgrade document');
INSERT INTO public.case_notes(id,matter_id,document_id,org_id,author_id,content)
VALUES('93500000-0000-0000-0000-000000000001','93300000-0000-0000-0000-000000000001','93400000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','93100000-0000-0000-0000-000000000001','Must survive constraint replacement');
INSERT INTO public.deadlines(id,matter_id,document_id,type,due_date)
VALUES('93600000-0000-0000-0000-000000000001','93300000-0000-0000-0000-000000000001','93400000-0000-0000-0000-000000000001','other',current_date);
INSERT INTO public.wiki_sections(id,matter_id,section_key,title,content)
VALUES('93700000-0000-0000-0000-000000000001','93300000-0000-0000-0000-000000000001','upgrade','Upgrade wiki','{}');
INSERT INTO public.wiki_section_versions(id,wiki_section_id,content,generated_by)
VALUES('93800000-0000-0000-0000-000000000001','93700000-0000-0000-0000-000000000001','{}','fixture');
