-- PlanTapDo Supabase bootstrap
--
-- Run once in the Supabase SQL editor as the project owner before Django
-- migrations. It never contains passwords; set them separately with psql's
-- interactive \password command so credentials do not enter source control,
-- shell history, or this script's SQL editor history.

begin;

do $roles$
begin
    if not exists (select 1 from pg_roles where rolname = 'plantapdo_migrator') then
        create role plantapdo_migrator
            noinherit login nosuperuser nocreatedb nocreaterole noreplication;
    end if;

    if not exists (select 1 from pg_roles where rolname = 'plantapdo_runtime') then
        create role plantapdo_runtime
            noinherit login nosuperuser nocreatedb nocreaterole noreplication;
    end if;
end
$roles$;

alter role plantapdo_migrator login;
alter role plantapdo_runtime login;

-- PostgreSQL permits ALTER DEFAULT PRIVILEGES only for the current role or a
-- role it belongs to. The Supabase project owner is already the administrative
-- trust boundary, so membership in the narrower migration role adds no runtime
-- access and allows the default grants below to be configured reliably.
grant plantapdo_migrator to current_user;

create schema if not exists plantapdo;
create schema if not exists plantapdo_security;
create extension if not exists pgcrypto with schema extensions;

-- The schema is an internal Django boundary, never a Supabase Data API
-- surface. Revoke both direct access and inherited PUBLIC access.
revoke all on schema plantapdo from public;
revoke all on schema plantapdo from anon, authenticated, service_role;
grant usage, create on schema plantapdo to plantapdo_migrator;
grant usage on schema plantapdo to plantapdo_runtime;

-- Runtime may execute the single tenant-context verifier but cannot read or
-- modify its signing key. The key is provisioned separately with psql so it
-- never appears in this repository or the SQL editor history.
revoke all on schema plantapdo_security from public;
revoke all on schema plantapdo_security from anon, authenticated, service_role;
grant usage on schema plantapdo_security to plantapdo_migrator, plantapdo_runtime;

create table if not exists plantapdo_security.tenant_context_secret (
    singleton boolean primary key default true check (singleton),
    secret bytea not null check (octet_length(secret) = 64)
);
revoke all on plantapdo_security.tenant_context_secret from public;
revoke all on plantapdo_security.tenant_context_secret
    from anon, authenticated, service_role, plantapdo_migrator, plantapdo_runtime;

create or replace function plantapdo_security.current_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, extensions, plantapdo_security
as $function$
declare
    tenant_text text;
    supplied_signature text;
    expected_signature text;
    signing_key bytea;
begin
    tenant_text := current_setting('plantapdo.tenant_id', true);
    supplied_signature := current_setting('plantapdo.tenant_signature', true);
    if tenant_text is null or supplied_signature is null then
        return null;
    end if;

    select secret into signing_key
    from plantapdo_security.tenant_context_secret
    where singleton;
    if signing_key is null then
        return null;
    end if;

    expected_signature := encode(
        hmac(convert_to(tenant_text, 'UTF8'), signing_key, 'sha256'),
        'hex'
    );
    if supplied_signature <> expected_signature then
        return null;
    end if;
    return tenant_text::uuid;
exception
    when invalid_text_representation then
        return null;
end
$function$;

revoke all on function plantapdo_security.current_tenant_id() from public;
revoke all on function plantapdo_security.current_tenant_id()
    from anon, authenticated, service_role;
grant execute on function plantapdo_security.current_tenant_id()
    to plantapdo_migrator, plantapdo_runtime;

-- Re-running the bootstrap after migrations repairs privileges on existing
-- objects. Django's migration role owns DDL; the API role receives DML only.
revoke all on all tables in schema plantapdo from public;
revoke all on all tables in schema plantapdo from anon, authenticated, service_role;
grant select, insert, update, delete
    on all tables in schema plantapdo to plantapdo_runtime;

revoke all on all sequences in schema plantapdo from public;
revoke all on all sequences in schema plantapdo from anon, authenticated, service_role;
grant usage, select, update
    on all sequences in schema plantapdo to plantapdo_runtime;

revoke execute on all functions in schema plantapdo from public;
revoke all on all functions in schema plantapdo from anon, authenticated, service_role;

-- Apply the same policy to every object created by future Django migrations.
alter default privileges for role plantapdo_migrator
    revoke all on tables from public;
alter default privileges for role plantapdo_migrator
    revoke all on tables from anon, authenticated, service_role;
alter default privileges for role plantapdo_migrator
    grant select, insert, update, delete on tables to plantapdo_runtime;

alter default privileges for role plantapdo_migrator
    revoke all on sequences from public;
alter default privileges for role plantapdo_migrator
    revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role plantapdo_migrator
    grant usage, select, update on sequences to plantapdo_runtime;

alter default privileges for role plantapdo_migrator
    revoke execute on functions from public;
alter default privileges for role plantapdo_migrator
    revoke all on functions from anon, authenticated, service_role;

alter default privileges for role plantapdo_migrator
    revoke usage on types from public;
alter default privileges for role plantapdo_migrator
    revoke all on types from anon, authenticated, service_role;
alter default privileges for role plantapdo_migrator
    grant usage on types to plantapdo_runtime;

alter role plantapdo_migrator set search_path = plantapdo;
alter role plantapdo_runtime set search_path = plantapdo;

commit;

-- Outside this script, use psql's interactive commands to assign two
-- independent generated passwords of at least 32 characters:
-- \password plantapdo_migrator
-- \password plantapdo_runtime
