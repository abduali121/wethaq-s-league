// أحداث الجولة المالية لكل فريق — نبني الجدول من balance_ledger (لأن عمود
// balance_after فيه الرصيد التراكمي الصحيح جاهز)، لكن نقرأ بس أسباب اقتصاد
// المباراة الحقيقية (نتيجة، رسم إعارة مدفوع/مستلم، خصم بدلة) ونتجاهل كليًا
// أي تصحيح/عكس إداري داخلي ما له علاقة بأحداث الجولة الفعلية.
const FINANCE_REASONS = ["match_result", "loan_fee", "loan_fee_credit", "kit_penalty"];

async function listTeamLedgerEvents(){
  const { data, error } = await sb
    .from("balance_ledger")
    .select(`
      id, team_id, delta, balance_after, reason, match_id, created_at,
      loan:loan_id( player_id, original_team_id, borrowing_team_id,
        player:player_id(id, full_name),
        original_team:original_team_id(id, name),
        borrowing_team:borrowing_team_id(id, name) )
    `)
    .in("reason", FINANCE_REASONS)
    .order("created_at", { ascending: true });
  if(error) throw error;
  return data;
}

// يربط كل مباراة برقم أسبوعها، عشان نقدر نفلتر جدول كل فريق بأسبوع محدد
async function listMatchWeeks(){
  const { data, error } = await sb.from("matches").select("id, week:week_id(week_number)");
  if(error) throw error;
  return data;
}

async function listKitMissingWithContext(matchIds){
  if(!matchIds.length) return [];
  const { data, error } = await sb
    .from("match_lineups")
    .select(`match_id, team_id, player:player_id(id, full_name, original_team_id)`)
    .in("match_id", matchIds)
    .eq("kit_missing", true);
  if(error) throw error;
  return data;
}
