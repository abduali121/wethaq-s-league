-- دوري وثاق: الكابتن (أو الإدارة) يختار شكل تشكيلته لكل مباراة من أربع صيغ ثابتة
-- (3-3 / 3-2-1 / 2-3-1 / 3-1-2 — كل رقم عدد لاعبين بخط، من الدفاع للهجوم، مجموعهم
-- 6 دائمًا + الحارس = 7). المراكز (position_slot) صارت ديناميكية حسب الشكل المختار،
-- فنوسّع القيد المسموح بدل القائمة الثابتة القديمة، ونمسح مراكز الفريق القديمة كل
-- ما يغيّر شكله (لأن معنى الخانات يتغيّر).
-- =============================================================================

alter table match_lineups drop constraint if exists match_lineups_position_slot_check;
alter table match_lineups add constraint match_lineups_position_slot_check
  check (position_slot is null or position_slot = 'GK' or position_slot ~ '^L[0-2]-[0-2]$');

create table match_lineup_formations (
  match_id  uuid not null references matches(id) on delete cascade,
  team_id   uuid not null references teams(id),
  formation text not null check (formation in ('3-3', '3-2-1', '2-3-1', '3-1-2')),
  updated_at timestamptz not null default now(),
  primary key (match_id, team_id)
);

alter table match_lineup_formations enable row level security;
create policy sel_match_lineup_formations on match_lineup_formations for select to authenticated, anon using (true);
grant select on match_lineup_formations to anon, authenticated;

create or replace function set_match_formation(p_match_id uuid, p_team_id uuid, p_formation text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_admin() or my_team_id() = p_team_id) then
    raise exception 'forbidden: not this team''s captain';
  end if;
  if p_formation not in ('3-3', '3-2-1', '2-3-1', '3-1-2') then
    raise exception 'invalid formation';
  end if;

  insert into match_lineup_formations (match_id, team_id, formation)
  values (p_match_id, p_team_id, p_formation)
  on conflict (match_id, team_id) do update set formation = excluded.formation, updated_at = now();

  -- معنى الخانات يتغيّر مع الشكل الجديد، فنصفّر مراكز هذا الفريق بهذي المباراة
  update match_lineups set position_slot = null where match_id = p_match_id and team_id = p_team_id;

  perform log_audit('set_match_formation', 'match_lineup_formations', p_match_id::text || ':' || p_team_id::text,
    null, jsonb_build_object('formation', p_formation));
end; $$;
grant execute on function set_match_formation(uuid, uuid, text) to authenticated;

-- نفس set_lineup_position (من 0041) بس التحقق من الخانة يطابق القيد الجديد بدل القائمة الثابتة
create or replace function set_lineup_position(p_match_id uuid, p_player_id uuid, p_slot text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_lineup match_lineups;
begin
  select * into v_lineup from match_lineups where match_id = p_match_id and player_id = p_player_id for update;
  if not found then raise exception 'player not in this match lineup'; end if;
  if not (is_admin() or my_team_id() = v_lineup.team_id) then
    raise exception 'forbidden: not this team''s captain';
  end if;
  if p_slot is not null and p_slot <> 'GK' and p_slot !~ '^L[0-2]-[0-2]$' then
    raise exception 'invalid slot';
  end if;

  if p_slot is not null then
    update match_lineups set position_slot = null
      where match_id = p_match_id and team_id = v_lineup.team_id and position_slot = p_slot and player_id <> p_player_id;
  end if;

  update match_lineups set position_slot = p_slot where id = v_lineup.id;
end; $$;
