async function listMatchGoals(matchId){
  const { data, error } = await sb.from("match_goals").select("*").eq("match_id", matchId);
  if(error) throw error;
  return data;
}

async function addMatchGoal(matchId, playerId){
  const { data, error } = await sb.rpc("add_match_goal", { p_match_id: matchId, p_player_id: playerId });
  if(error) throw error;
  return data;
}

async function removeMatchGoal(matchId, playerId){
  const { data, error } = await sb.rpc("remove_last_match_goal", { p_match_id: matchId, p_player_id: playerId });
  if(error) throw error;
  return data;
}

async function listTopScorers(limit = 10){
  const { data, error } = await sb.from("top_scorers").select("*").order("goals", { ascending: false }).limit(limit);
  if(error) throw error;
  return data;
}
