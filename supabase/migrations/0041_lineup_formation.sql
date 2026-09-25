-- دوري وثاق: يقدر كل كابتن يحدد مركز كل لاعب من تشكيلته على ملعب حقيقي (تشكيلة
-- ثابتة 1-2-3-1: حارس + مدافعان + ثلاثة وسط + مهاجم = 7 لاعبين، تطابق قاعدة
-- "7 لاعبين بالملعب مع الحارس"). المراكز اختيارية — التشكيلة تشتغل بدونها عادي.
-- =============================================================================

alter table match_lineups add column position_slot text
  check (position_slot is null or position_slot in ('GK','DF1','DF2','MF1','MF2','MF3','FW1'));

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
  if p_slot is not null and p_slot not in ('GK','DF1','DF2','MF1','MF2','MF3','FW1') then
    raise exception 'invalid slot';
  end if;

  -- لو المركز محجوز للاعب ثاني بنفس الفريق بهذي المباراة، يفضّى منه تلقائيًا (تبديل)
  if p_slot is not null then
    update match_lineups set position_slot = null
      where match_id = p_match_id and team_id = v_lineup.team_id and position_slot = p_slot and player_id <> p_player_id;
  end if;

  update match_lineups set position_slot = p_slot where id = v_lineup.id;
end; $$;

grant execute on function set_lineup_position(uuid, uuid, text) to authenticated;
