-- Buckets and the policies on storage.objects. Public buckets serve every file to anyone with the path;
-- policies for user files should compare the folder with the user's id,
-- for example (storage.foldername(name))[1] = (select auth.uid())::text.
select id as bucket, public from storage.buckets order by 1;
select policyname, cmd, roles, qual, with_check from pg_policies
where schemaname = 'storage' and tablename = 'objects' order by 1;
