-- دوري وثاق: تسجيل الأهداف الفعلية لكل مباراة (مين سجّل، وكم مرة) — منفصل تمامًا
-- عن منطق تحديد الفائز/توزيع الفلوس (اللي يبقى زي ما هو، فائز واحد بس، بدون تعادل).
-- هدف واحد = صف واحد، فاللاعب اللي سجّل 3 أهداف له 3 صفوف — يسمح بإضافة/حذف هدف
-- بضغطة وحدة (زي زيادة/إنقاص كمية بسلة تسوق). تُستخدم لعرض قائمة الهدافين.
-- =============================================================================

create table match_goals (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references matches(id) on delete cascade,
  player_id   uuid not null references players(id),
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now()
);

alter table match_goals enable row level security;
create policy sel_match_goals on match_goals for select to authenticated, anon using (true);
grant select on match_goals to anon, authenticated;

create or replace function add_match_goal(p_match_id uuid, p_player_id uuid)
returns match_goals
language plpgsql security definer set search_path = public as $$
declare
  v_goal match_goals;
  v_exists boolean;
begin
  if not is_admin() then raise exception 'forbidden: admin only'; end if;

  select exists(select 1 from match_lineups where match_id = p_match_id and player_id = p_player_id) into v_exists;
  if not v_exists then raise exception 'player is not in this match lineup'; end if;

  insert into match_goals (match_id, player_id, created_by)
  values (p_match_id, p_player_id, auth.uid())
  returning * into v_goal;

  perform log_audit('add_match_goal', 'match_goals', v_goal.id::text, null, to_jsonb(v_goal));
  return v_goal;
end; $$;
grant execute on function add_match_goal(uuid, uuid) to authenticated;

create or replace function remove_last_match_goal(p_match_id uuid, p_player_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_goal match_goals;
begin
  if not is_admin() then raise exception 'forbidden: admin only'; end if;

  select * into v_goal from match_goals
    where match_id = p_match_id and player_id = p_player_id
    order by created_at desc limit 1;
  if not found then raise exception 'no goal to remove'; end if;

  delete from match_goals where id = v_goal.id;
  perform log_audit('remove_last_match_goal', 'match_goals', v_goal.id::text, to_jsonb(v_goal), null);
end; $$;
grant execute on function remove_last_match_goal(uuid, uuid) to authenticated;

-- قائمة الهدافين — إجمالي أهداف كل لاعب عبر كل مباريات الدوري
create view top_scorers as
  select
    p.id as player_id,
    p.full_name,
    p.original_team_id as team_id,
    t.name as team_name,
    count(mg.id) as goals
  from players p
  join teams t on t.id = p.original_team_id
  join match_goals mg on mg.player_id = p.id
  group by p.id, p.full_name, p.original_team_id, t.name
  order by count(mg.id) desc, p.full_name asc;

grant select on top_scorers to anon, authenticated;
