// سجل كل الحركات المالية لكل الفرق، مع الأطراف والسياق اللازم لعرضها بجمل عربية
// واضحة (مين لعب مين، أي أسبوع، أي لاعب مُعار) بدل أسماء الأعمدة التقنية الخام.
async function listAllLedgerWithContext(){
  const { data, error } = await sb
    .from("balance_ledger")
    .select(`
      *,
      match:match_id( id, team_a_id, team_b_id,
        week:week_id(week_number),
        team_a:team_a_id(name), team_b:team_b_id(name) ),
      loan:loan_id( player_id, original_team_id, borrowing_team_id,
        player:player_id(full_name),
        original_team:original_team_id(name),
        borrowing_team:borrowing_team_id(name) )
    `)
    .order("created_at", { ascending: false });
  if(error) throw error;
  return data;
}
