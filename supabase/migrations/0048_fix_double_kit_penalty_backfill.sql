-- دوري وثاق: تصحيح خطأ ارتكبته migration 0047 نفسها. الباكفل فيها أعاد تطبيق أي
-- خصم بدلة (kit_penalty) سبق وانعكس تاريخيًا، بدون ما يتحقق هل الإدارة أصلاً
-- أعادت تسجيل "بدون بدلة" يدويًا بنفسها قبل الاعتماد النهائي للمباراة (ممكن لأن
-- set_lineup يمسح وييعيد إنشاء صفوف match_lineups من الصفر، فتصفر علامة
-- kit_missing ويسمح بتسجيلها من جديد عادي). بالضبط هذا صار لسطوة وماريو الهداف:
-- الإدارة سجّلت "بدون بدلة" يدويًا من جديد (صف شرعي غير معكوس أبدًا، لسا قائم
-- بالسجل) قبل الاعتماد الأخير، فلما الباكفل طبّق فوقه خصم الجولة القديمة المعكوسة
-- زيادة، تكرر نفس الـ40 مرتين على كل فريق.
-- =============================================================================

do $$
declare
  v_team record;
  v_already_corrected boolean;
begin
  for v_team in
    select distinct team_id, match_id from balance_ledger
    where note like 'إعادة تطبيق خصم بدلة فُقد بسبب إلغاء/إعادة اعتماد المباراة%'
  loop
    select exists(
      select 1 from balance_ledger
      where team_id = v_team.team_id and match_id = v_team.match_id
        and reason = 'admin_adjustment'
        and note = 'تصحيح: إلغاء خصم بدلة مكرر طبّقته migration 0047 خطأً فوق خصم شرعي أعادت الإدارة تسجيله يدويًا'
    ) into v_already_corrected;
    if v_already_corrected then continue; end if;

    insert into balance_ledger (team_id, delta, balance_after, reason, match_id, note)
    values (v_team.team_id, 40,
      (select balance_wathaq from teams where id = v_team.team_id) + 40,
      'admin_adjustment', v_team.match_id,
      'تصحيح: إلغاء خصم بدلة مكرر طبّقته migration 0047 خطأً فوق خصم شرعي أعادت الإدارة تسجيله يدويًا');

    update teams set balance_wathaq = balance_wathaq + 40 where id = v_team.team_id;
  end loop;
end $$;
