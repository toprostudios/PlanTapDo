-- Run after Django migrations. Re-running is safe.

begin;

alter table plantapdo.timetodo_api_category enable row level security;
alter table plantapdo.timetodo_api_todoentry enable row level security;
alter table plantapdo.timetodo_api_locationtraveltime enable row level security;
alter table plantapdo.timetodo_api_timesession enable row level security;
alter table plantapdo.timetodo_api_repeatrule enable row level security;

drop policy if exists category_tenant_isolation on plantapdo.timetodo_api_category;
create policy category_tenant_isolation on plantapdo.timetodo_api_category
    for all to plantapdo_runtime
    using (owner_id = plantapdo_security.current_tenant_id())
    with check (owner_id = plantapdo_security.current_tenant_id());

drop policy if exists todo_tenant_isolation on plantapdo.timetodo_api_todoentry;
create policy todo_tenant_isolation on plantapdo.timetodo_api_todoentry
    for all to plantapdo_runtime
    using (owner_id = plantapdo_security.current_tenant_id())
    with check (owner_id = plantapdo_security.current_tenant_id());

drop policy if exists travel_time_tenant_isolation on plantapdo.timetodo_api_locationtraveltime;
create policy travel_time_tenant_isolation on plantapdo.timetodo_api_locationtraveltime
    for all to plantapdo_runtime
    using (owner_id = plantapdo_security.current_tenant_id())
    with check (owner_id = plantapdo_security.current_tenant_id());

drop policy if exists time_session_tenant_isolation on plantapdo.timetodo_api_timesession;
create policy time_session_tenant_isolation on plantapdo.timetodo_api_timesession
    for all to plantapdo_runtime
    using (
        exists (
            select 1
            from plantapdo.timetodo_api_todoentry todo
            where todo.id = todo_id
              and todo.owner_id = plantapdo_security.current_tenant_id()
        )
    )
    with check (
        exists (
            select 1
            from plantapdo.timetodo_api_todoentry todo
            where todo.id = todo_id
              and todo.owner_id = plantapdo_security.current_tenant_id()
        )
    );

drop policy if exists repeat_rule_tenant_isolation on plantapdo.timetodo_api_repeatrule;
create policy repeat_rule_tenant_isolation on plantapdo.timetodo_api_repeatrule
    for all to plantapdo_runtime
    using (
        exists (
            select 1
            from plantapdo.timetodo_api_todoentry todo
            where todo.id = todo_id
              and todo.owner_id = plantapdo_security.current_tenant_id()
        )
    )
    with check (
        exists (
            select 1
            from plantapdo.timetodo_api_todoentry todo
            where todo.id = todo_id
              and todo.owner_id = plantapdo_security.current_tenant_id()
        )
    );

commit;
