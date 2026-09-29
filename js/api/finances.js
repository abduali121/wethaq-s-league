// أحداث الجولة المالية — تُبنى مباشرة من مصادرها الحقيقية (نتيجة المباراة،
// صفقات الإعارة، خصم البدلة) بدل سجل balance_ledger الخام اللي فيه ضجيج تقني
// (تصحيحات/عكس حركات بعد الإلغاء) ما يهم أحد غير الإدارة.

async function listFinancialMatches(){
  const { data, error } = await sb
    .from("matches")
    .select(`
      id, team_a_stake, team_b_stake, winner_team_id, confirmed_at,
      team_a_balance_after, team_b_balance_after,
      week:week_id(week_number),
      team_a:team_a_id(id,name,primary_color),
      team_b:team_b_id(id,name,primary_color)
    `)
    .eq("status", "completed")
    .order("confirmed_at", { ascending: false });
  if(error) throw error;
  return data;
}

async function listMatchLoansWithContext(matchIds){
  if(!matchIds.length) return [];
  const { data, error } = await sb
    .from("match_loans")
    .select(`
      match_id, winning_bid_amount, fee_settled,
      player:player_id(id, full_name),
      original_team:original_team_id(id, name),
      borrowing_team:borrowing_team_id(id, name)
    `)
    .in("match_id", matchIds);
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
