-- دوري وثاق: تصحيح خطأ ارتكبته migration 0048 نفسها. هي افترضت إن كل خصم بدلة
-- أعادت migration 0047 تطبيقه كان خطأ مكرر (double-count) — بس هذا صحيح بس بحالة
-- سطوة وماريو الهداف (اللي الإدارة أعادت تسجيل "بدون بدلة" يدويًا بنفسها بعد
-- الإلغاء، قبل الاعتماد الأخير). بحالة السلاجقة والسيل الكبير ما فيه أي إعادة
-- تسجيل يدوية جديدة بعد الإلغاء — يعني خصم migration 0047 كان صحيحًا أصلًا ولازم
-- يبقى، و migration 0048 غلطت لما رجعت الـ40 لهذي الحالة.
--
-- القاعدة اللي نميّز فيها الحالتين: هل فيه صف kit_penalty "طازج" (بدون ملاحظة،
-- يعني مسجّل يدويًا بالطريقة العادية) لنفس الفريق والمباراة بعد آخر عملية إلغاء
-- اعتماد لهذي المباراة؟ لو موجود => خصم 0047 كان مكرر فعلًا (0048 صحيحة، نتركها).
-- لو مو موجود => خصم 0047 كان صحيحًا من الأساس (0048 غلط، نرجع نصححها).
-- =============================================================================

do $$
declare
  v_fix record;
  v_last_reversal_at timestamptz;
  v_has_fresh_penalty boolean;
  v_already_fixed boolean;
begin
  for v_fix in
    select * from balance_ledger
    where reason = 'admin_adjustment'
      and note = 'تصحيح: إلغاء خصم بدلة مكرر طبّقته migration 0047 خطأً فوق خصم شرعي أعادت الإدارة تسجيله يدويًا'
  loop
    select max(created_at) into v_last_reversal_at
    from balance_ledger
    where match_id = v_fix.match_id and reason = 'admin_reversal';

    select exists(
      select 1 from balance_ledger
      where team_id = v_fix.team_id and match_id = v_fix.match_id
        and reason = 'kit_penalty' and note is null
        and (v_last_reversal_at is null or created_at > v_last_reversal_at)
    ) into v_has_fresh_penalty;

    if not v_has_fresh_penalty then
      select exists(
        select 1 from balance_ledger
        where team_id = v_fix.team_id and match_id = v_fix.match_id
          and reason = 'admin_adjustment'
          and note = 'تصحيح ثانٍ: تراجع عن تصحيح migration 0048 الخاطئ — خصم migration 0047 كان صحيحًا أصلًا'
      ) into v_already_fixed;
      if v_already_fixed then continue; end if;

      insert into balance_ledger (team_id, delta, balance_after, reason, match_id, note)
      values (v_fix.team_id, -40,
        (select balance_wathaq from teams where id = v_fix.team_id) - 40,
        'admin_adjustment', v_fix.match_id,
        'تصحيح ثانٍ: تراجع عن تصحيح migration 0048 الخاطئ — خصم migration 0047 كان صحيحًا أصلًا');

      update teams set balance_wathaq = balance_wathaq - 40 where id = v_fix.team_id;
    end if;
  end loop;
end $$;
