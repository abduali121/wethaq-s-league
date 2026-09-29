-- دوري وثاق: تصحيح خطأ حقيقي — undo_match_result كانت تعكس كل صفوف balance_ledger
-- المرتبطة بالمباراة بلا استثناء، بما فيها 'kit_penalty'. بس حسب تصميم خصم البدلة
-- الأصلي (migration 0040)، خصم اللاعب الأصلي "فوري وثابت... بغض النظر عن نتيجة
-- المباراة" — يعني مفروض يكون مستقل تمامًا عن اعتماد/إلغاء نتيجة المباراة، ما يصح
-- ينعكس معها. النتيجة: أي مباراة اتلغي اعتمادها بعد ما يتسجل عليها خصم بدلة، ثم
-- اعتُمدت نتيجتها من جديد، يضيع خصم البدلة نهائيًا (يرجع فلوسه بس ما يترجع تاني)
-- بينما علامة "بدون بدلة" تبقى ظاهرة باللاعب وكأنه مخصوم عليه — فيصير رصيد الفريق
-- أعلى من الصحيح بمقدار كل خصم بدلة ضاع بهذي الطريقة.
-- =============================================================================

create or replace function undo_match_result(p_match_id uuid) returns matches
language plpgsql security definer set search_path = public as $$
declare
  v_match matches;
  v_row record;
begin
  if not is_admin() then raise exception 'forbidden: admin only'; end if;

  select * into v_match from matches where id = p_match_id for update;
  if not found then raise exception 'match not found'; end if;
  if v_match.status <> 'completed' then raise exception 'match is not completed, nothing to undo'; end if;

  -- عكس صفوف السجل المالي المرتبطة بنتيجة المباراة نفسها (تسوية + رسوم إعارة) بس —
  -- خصم البدلة (kit_penalty) مستقل عن اعتماد النتيجة فما يُعكس أبدًا هنا
  for v_row in select * from balance_ledger where match_id = p_match_id and reason <> 'kit_penalty' loop
    insert into balance_ledger (team_id, delta, balance_after, reason, match_id, loan_id, note, created_by)
    values (v_row.team_id, -v_row.delta,
      (select balance_wathaq from teams where id = v_row.team_id) - v_row.delta,
      'admin_reversal', p_match_id, v_row.loan_id, 'reversal of ledger #' || v_row.id, auth.uid());
    update teams set balance_wathaq = balance_wathaq - v_row.delta where id = v_row.team_id;
  end loop;

  update match_loans set fee_settled = false where match_id = p_match_id;

  update matches set
    status = 'scheduled', winner_team_id = null,
    team_a_balance_before = null, team_b_balance_before = null,
    team_a_balance_after = null, team_b_balance_after = null,
    confirmed_at = null, confirmed_by = null
  where id = p_match_id
  returning * into v_match;

  delete from standings_snapshots where week_id = v_match.week_id;

  perform log_audit('undo_match_result', 'matches', p_match_id::text, null, to_jsonb(v_match));
  return v_match;
end; $$;

-- تعويض بأثر رجعي: أي خصم بدلة (kit_penalty) سبق وانعكس بواسطة undo_match_result
-- القديمة، نطبّقه من جديد (نفس المبلغ بالضبط) لأنه ما كان يفترض ينعكس أصلًا
do $$
declare
  v_orig record;
  v_already_reapplied boolean;
begin
  for v_orig in
    select bl.* from balance_ledger bl
    where bl.reason = 'kit_penalty'
      and exists (
        select 1 from balance_ledger r
        where r.reason = 'admin_reversal' and r.note = 'reversal of ledger #' || bl.id
      )
  loop
    select exists(
      select 1 from balance_ledger
      where reason = 'kit_penalty' and match_id = v_orig.match_id and team_id = v_orig.team_id
        and note = 'إعادة تطبيق خصم بدلة فُقد بسبب إلغاء/إعادة اعتماد المباراة (تصحيح لسجل #' || v_orig.id || ')'
    ) into v_already_reapplied;
    if v_already_reapplied then continue; end if;

    insert into balance_ledger (team_id, delta, balance_after, reason, match_id, note)
    values (v_orig.team_id, v_orig.delta,
      (select balance_wathaq from teams where id = v_orig.team_id) + v_orig.delta,
      'kit_penalty', v_orig.match_id,
      'إعادة تطبيق خصم بدلة فُقد بسبب إلغاء/إعادة اعتماد المباراة (تصحيح لسجل #' || v_orig.id || ')');

    update teams set balance_wathaq = balance_wathaq + v_orig.delta where id = v_orig.team_id;
  end loop;
end $$;
