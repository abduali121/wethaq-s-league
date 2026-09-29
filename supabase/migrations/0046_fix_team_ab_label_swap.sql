-- دوري وثاق: تصحيح خطأ حقيقي موروث — confirm_match_result كانت تقفل صفّي الفريقين
-- بترتيب ثابت (least/greatest) لتفادي deadlock عند التزامن، لكنها بعدين كانت تستخدم
-- نفس المتغيّرين (v_team_a/v_team_b) كأنهم "فريق أ/ب الفعليين بالمباراة" عند تسجيل
-- team_a_balance_before/after — فلو كان معرّف team_b_id أصغر أبجديًا من team_a_id،
-- الأرقام تنكتب معكوسة (تحت اسم فريق أ تطلع أرقام فريق ب والعكس) بلوحة الإدارة.
-- هذا ما يأثر على رصيد أي فريق فعليًا (الجدول teams سليم دايمًا)، بس يصحّح العرض.
-- =============================================================================

create or replace function confirm_match_result(
  p_match_id uuid, p_winner_team_id uuid
) returns matches
language plpgsql security definer set search_path = public as $$
declare
  v_match matches;
  v_loser_team_id uuid;
  v_team_a teams; v_team_b teams;
  v_winner teams; v_loser teams;
  v_winner_stake integer; v_loser_stake integer;
  v_loan record;
  v_kit_missing boolean;
  v_fee_amount integer;
  v_prediction record;
  v_week_number integer;
  v_rank integer;
  v_team record;
begin
  if not is_admin() then raise exception 'forbidden: admin only'; end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'match not found'; end if;
  if v_match.status = 'completed' then raise exception 'match already completed'; end if;
  if v_match.status = 'cancelled' then raise exception 'match is cancelled'; end if;
  if p_winner_team_id not in (v_match.team_a_id, v_match.team_b_id) then
    raise exception 'winner must be one of the two participating teams';
  end if;

  v_loser_team_id := case when p_winner_team_id = v_match.team_a_id then v_match.team_b_id else v_match.team_a_id end;

  -- نقفل الفريقين بترتيب ثابت (تفادي deadlock) بس القفل هذا لغرض التزامن فقط —
  -- ما يحدد مين "فريق أ" فعليًا، فنجيب بيانات team_a/team_b الحقيقية بعده بالـid الصح
  perform 1 from teams where id = least(v_match.team_a_id, v_match.team_b_id) for update;
  perform 1 from teams where id = greatest(v_match.team_a_id, v_match.team_b_id) for update;
  select * into v_team_a from teams where id = v_match.team_a_id;
  select * into v_team_b from teams where id = v_match.team_b_id;

  v_winner := case when v_team_a.id = p_winner_team_id then v_team_a else v_team_b end;
  v_loser  := case when v_team_a.id = v_loser_team_id then v_team_a else v_team_b end;

  v_winner_stake := case when p_winner_team_id = v_match.team_a_id then v_match.team_a_stake else v_match.team_b_stake end;
  v_loser_stake  := case when v_loser_team_id  = v_match.team_a_id then v_match.team_a_stake else v_match.team_b_stake end;

  if v_loser_stake > v_loser.balance_wathaq then
    raise exception 'the losing team''s own stake (%) exceeds its current balance (%)', v_loser_stake, v_loser.balance_wathaq;
  end if;

  insert into balance_ledger (team_id, delta, balance_after, reason, match_id, created_by)
  values (v_winner.id, v_winner_stake, v_winner.balance_wathaq + v_winner_stake, 'match_result', p_match_id, auth.uid());
  insert into balance_ledger (team_id, delta, balance_after, reason, match_id, created_by)
  values (v_loser.id, -v_loser_stake, v_loser.balance_wathaq - v_loser_stake, 'match_result', p_match_id, auth.uid());

  update teams set balance_wathaq = balance_wathaq + v_winner_stake where id = v_winner.id;
  update teams set balance_wathaq = balance_wathaq - v_loser_stake where id = v_loser.id;

  for v_loan in
    select * from match_loans
    where match_id = p_match_id and borrowing_team_id = p_winner_team_id and not fee_settled
  loop
    select coalesce(kit_missing, false) into v_kit_missing from match_lineups
      where match_id = p_match_id and player_id = v_loan.player_id;
    v_fee_amount := case when v_kit_missing then ceil(v_loan.winning_bid_amount / 2.0)::integer else v_loan.winning_bid_amount end;

    insert into balance_ledger (team_id, delta, balance_after, reason, match_id, loan_id, created_by)
    values (v_loan.borrowing_team_id, -v_fee_amount,
      (select balance_wathaq from teams where id = v_loan.borrowing_team_id) - v_fee_amount,
      'loan_fee', p_match_id, v_loan.id, auth.uid());
    update teams set balance_wathaq = balance_wathaq - v_fee_amount where id = v_loan.borrowing_team_id;

    insert into balance_ledger (team_id, delta, balance_after, reason, match_id, loan_id, created_by)
    values (v_loan.original_team_id, v_fee_amount,
      (select balance_wathaq from teams where id = v_loan.original_team_id) + v_fee_amount,
      'loan_fee_credit', p_match_id, v_loan.id, auth.uid());
    update teams set balance_wathaq = balance_wathaq + v_fee_amount where id = v_loan.original_team_id;

    update match_loans set fee_settled = true where id = v_loan.id;
  end loop;

  if v_match.prediction_enabled and v_match.prediction_reward is not null then
    for v_prediction in
      select * from match_predictions
      where match_id = p_match_id and predicted_winner_team_id = p_winner_team_id
    loop
      insert into balance_ledger (team_id, delta, balance_after, reason, match_id, created_by)
      values (v_prediction.predicting_team_id, v_match.prediction_reward,
        (select balance_wathaq from teams where id = v_prediction.predicting_team_id) + v_match.prediction_reward,
        'prediction_reward', p_match_id, auth.uid());

      update teams set balance_wathaq = balance_wathaq + v_match.prediction_reward where id = v_prediction.predicting_team_id;
    end loop;
  end if;

  update matches set
    status = 'completed',
    winner_team_id = p_winner_team_id,
    team_a_balance_before = v_team_a.balance_wathaq,
    team_b_balance_before = v_team_b.balance_wathaq,
    team_a_balance_after = (select balance_wathaq from teams where id = v_team_a.id),
    team_b_balance_after = (select balance_wathaq from teams where id = v_team_b.id),
    confirmed_at = now(),
    confirmed_by = auth.uid()
  where id = p_match_id
  returning * into v_match;

  select week_number into v_week_number from weeks where id = v_match.week_id;

  v_rank := 0;
  for v_team in
    select t.id, t.balance_wathaq,
      (select count(*) from matches m where m.status='completed' and m.winner_team_id = t.id) as wins,
      (select count(*) from matches m where m.status='completed' and m.winner_team_id <> t.id and t.id in (m.team_a_id, m.team_b_id)) as losses
    from teams t
    order by t.balance_wathaq desc, t.name asc
  loop
    v_rank := v_rank + 1;
    insert into standings_snapshots (week_id, team_id, balance_wathaq, wins, losses, rank)
    values (v_match.week_id, v_team.id, v_team.balance_wathaq, v_team.wins, v_team.losses, v_rank)
    on conflict (week_id, team_id) do update
      set balance_wathaq = excluded.balance_wathaq, wins = excluded.wins,
          losses = excluded.losses, rank = excluded.rank;
  end loop;

  perform log_audit('confirm_match_result', 'matches', p_match_id::text,
    jsonb_build_object('status', 'scheduled'), to_jsonb(v_match));

  return v_match;
end; $$;

-- تصحيح بأثر رجعي لأي مباراة سبق واعتُمدت بأرقام معكوسة (فقط تصحيح عمودي العرض،
-- ما يغيّر أي رصيد فعلي بجدول teams)
update matches m set
  team_a_balance_before = case when m.team_a_id = least(m.team_a_id, m.team_b_id) then m.team_a_balance_before else m.team_b_balance_before end,
  team_b_balance_before = case when m.team_a_id = least(m.team_a_id, m.team_b_id) then m.team_b_balance_before else m.team_a_balance_before end,
  team_a_balance_after  = case when m.team_a_id = least(m.team_a_id, m.team_b_id) then m.team_a_balance_after  else m.team_b_balance_after  end,
  team_b_balance_after  = case when m.team_a_id = least(m.team_a_id, m.team_b_id) then m.team_b_balance_after  else m.team_a_balance_after  end
where m.status = 'completed' and m.team_a_id <> least(m.team_a_id, m.team_b_id);
