-- Run in the Supabase SQL editor after bootstrap.sql and after every migration.
-- A successful run returns without an exception.

do $verification$
declare
    role_name text;
    privilege_name text;
    object_record record;
begin
    if not exists (select 1 from pg_namespace where nspname = 'plantapdo') then
        raise exception 'plantapdo schema does not exist';
    end if;
    if not exists (
        select 1 from plantapdo_security.tenant_context_secret where singleton
    ) then
        raise exception 'tenant-context signing key has not been provisioned';
    end if;

    if exists (
        select 1
        from pg_roles
        where rolname in ('plantapdo_migrator', 'plantapdo_runtime')
          and (
              not rolcanlogin
              or rolsuper
              or rolcreatedb
              or rolcreaterole
              or rolreplication
              or rolbypassrls
          )
    ) then
        raise exception 'PlanTapDo database roles have unsafe role attributes';
    end if;

    if not has_schema_privilege('plantapdo_migrator', 'plantapdo', 'CREATE') then
        raise exception 'migration role cannot create objects in plantapdo';
    end if;
    if not has_schema_privilege('plantapdo_runtime', 'plantapdo', 'USAGE') then
        raise exception 'runtime role cannot use plantapdo';
    end if;
    if has_schema_privilege('plantapdo_runtime', 'plantapdo', 'CREATE') then
        raise exception 'runtime role can create objects in plantapdo';
    end if;
    if has_table_privilege(
        'plantapdo_runtime',
        'plantapdo_security.tenant_context_secret',
        'SELECT'
    ) then
        raise exception 'runtime can read the tenant-context signing key';
    end if;
    if not has_function_privilege(
        'plantapdo_runtime',
        'plantapdo_security.current_tenant_id()',
        'EXECUTE'
    ) then
        raise exception 'runtime cannot execute the tenant-context verifier';
    end if;

    foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
        if has_schema_privilege(role_name, 'plantapdo', 'USAGE') then
            raise exception '% unexpectedly has schema access', role_name;
        end if;
    end loop;

    for object_record in
        select
            format('%I.%I', n.nspname, c.relname) as qualified_name,
            pg_get_userbyid(c.relowner) as object_owner
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'plantapdo'
          and c.relkind in ('r', 'p', 'v', 'm', 'f')
    loop
        if object_record.object_owner <> 'plantapdo_migrator' then
            raise exception '% is owned by %, not plantapdo_migrator',
                object_record.qualified_name,
                object_record.object_owner;
        end if;

        foreach privilege_name in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
            if not has_table_privilege(
                'plantapdo_runtime',
                object_record.qualified_name,
                privilege_name
            ) then
                raise exception 'runtime lacks % on %',
                    privilege_name,
                    object_record.qualified_name;
            end if;
        end loop;

        foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
            foreach privilege_name in array array[
                'SELECT', 'INSERT', 'UPDATE', 'DELETE',
                'TRUNCATE', 'REFERENCES', 'TRIGGER'
            ] loop
                if has_table_privilege(
                    role_name,
                    object_record.qualified_name,
                    privilege_name
                ) then
                    raise exception '% unexpectedly has % on %',
                        role_name,
                        privilege_name,
                        object_record.qualified_name;
                end if;
            end loop;
        end loop;
    end loop;

    if exists (
        select 1
        from (values
            ('timetodo_api_category'),
            ('timetodo_api_todoentry'),
            ('timetodo_api_locationtraveltime'),
            ('timetodo_api_timesession'),
            ('timetodo_api_repeatrule')
        ) as required_table(table_name)
        where not exists (
            select 1
            from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'plantapdo'
              and c.relname = required_table.table_name
              and c.relrowsecurity
        )
    ) then
        raise exception 'one or more tenant tables do not have RLS enabled';
    end if;

    for object_record in
        select
            format('%I.%I', n.nspname, c.relname) as qualified_name,
            pg_get_userbyid(c.relowner) as object_owner
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'plantapdo'
          and c.relkind = 'S'
    loop
        if object_record.object_owner <> 'plantapdo_migrator' then
            raise exception '% is owned by %, not plantapdo_migrator',
                object_record.qualified_name,
                object_record.object_owner;
        end if;

        foreach privilege_name in array array['USAGE', 'SELECT', 'UPDATE'] loop
            if not has_sequence_privilege(
                'plantapdo_runtime',
                object_record.qualified_name,
                privilege_name
            ) then
                raise exception 'runtime lacks % on %',
                    privilege_name,
                    object_record.qualified_name;
            end if;
        end loop;

        foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
            foreach privilege_name in array array['USAGE', 'SELECT', 'UPDATE'] loop
                if has_sequence_privilege(
                    role_name,
                    object_record.qualified_name,
                    privilege_name
                ) then
                    raise exception '% unexpectedly has % on %',
                        role_name,
                        privilege_name,
                        object_record.qualified_name;
                end if;
            end loop;
        end loop;
    end loop;

    for object_record in
        select p.oid, format('%I.%I', n.nspname, p.proname) as qualified_name
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'plantapdo'
    loop
        foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
            if has_function_privilege(role_name, object_record.oid, 'EXECUTE') then
                raise exception '% unexpectedly can execute %',
                    role_name,
                    object_record.qualified_name;
            end if;
        end loop;
    end loop;
end
$verification$;

select
    n.nspname as schema_name,
    pg_get_userbyid(n.nspowner) as schema_owner,
    has_schema_privilege('plantapdo_runtime', n.oid, 'USAGE') as runtime_can_use,
    has_schema_privilege('plantapdo_runtime', n.oid, 'CREATE') as runtime_can_create
from pg_namespace n
where n.nspname = 'plantapdo';
