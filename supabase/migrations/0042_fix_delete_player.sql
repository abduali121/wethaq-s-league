-- دوري وثاق: إصلاح خطأ قديم موروث — delete_player كانت تحاول تحذف من جدول
-- "auctions" اللي انحذف كليًا من المشروع بميغريشن 0011 (نظام المزايدة القديم
-- استُبدل بالتعاقد المباشر)، فكل محاولة حذف لاعب كانت تفشل بخطأ
-- "relation auctions does not exist".
-- =============================================================================

create or replace function delete_player(p_player_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_player players;
  v_lineup_count integer;
  v_loan_count integer;
  v_claim_count integer;
begin
  if not is_admin() then raise exception 'forbidden: admin only'; end if;

  select * into v_player from players where id = p_player_id;
  if not found then raise exception 'player not found'; end if;

  select count(*) into v_lineup_count from match_lineups where player_id = p_player_id;
  if v_lineup_count > 0 then
    raise exception 'cannot delete a player who already appears in a match lineup';
  end if;

  select count(*) into v_loan_count from match_loans where player_id = p_player_id;
  if v_loan_count > 0 then
    raise exception 'cannot delete a player who has an existing loan record';
  end if;

  select count(*) into v_claim_count from loan_claims where player_id = p_player_id;
  if v_claim_count > 0 then
    raise exception 'cannot delete a player who has an existing loan claim';
  end if;

  delete from players where id = p_player_id;
  perform log_audit('delete_player', 'players', p_player_id::text, to_jsonb(v_player), null);
end; $$;
