// أحداث الجولة المالية لكل فريق — تُبنى من الحالة الحالية الحقيقية لمصادرها
// (نتيجة المباراة + صفقات الإعارة + خصم البدلة) بدل الاعتماد على تاريخ
// balance_ledger الخام. السبب: مباريات اتلغى اعتمادها وأُعيد اعتمادها أكثر
// من مرة أثناء الاختبار تترك صفوف "عكس" بالسجل، فلو عرضنا السجل كما هو
// يطلع نفس الحدث مكرر عدة مرات رغم إن الرصيد الفعلي صحيح. بالطريقة هذي، كل
// حدث معروض هو حدث حقيقي قائم الآن بس، والرصيد التراكمي يوصل دائمًا لنفس
// رصيد الفريق الحقيقي بالضبط.

async function loadFinancialData(){
  const [matches, loans, kitRows] = await Promise.all([
    sb.from("matches")
      .select(`id, team_a_id, team_b_id, team_a_stake, team_b_stake, winner_team_id, confirmed_at, week:week_id(week_number)`)
      .eq("status", "completed")
      .then(r => { if(r.error) throw r.error; return r.data; }),
    sb.from("match_loans")
      .select(`match_id, player_id, original_team_id, borrowing_team_id, winning_bid_amount, fee_settled, player:player_id(full_name)`)
      .eq("fee_settled", true)
      .then(r => { if(r.error) throw r.error; return r.data; }),
    sb.from("match_lineups")
      .select(`match_id, team_id, player:player_id(id, full_name, original_team_id)`)
      .eq("kit_missing", true)
      .then(r => { if(r.error) throw r.error; return r.data; }),
  ]);
  return { matches, loans, kitRows };
}

// يبني قائمة كل الأحداث المالية الحقيقية (القائمة الآن) لكل فريق، مرتّبة زمنيًا،
// مع رصيد تراكمي يوصل بالضبط لرصيد الفريق الحالي — بدون أي تكرار من محاولات
// اعتماد/إلغاء سابقة
function buildTeamEvents(teams, { matches, loans, kitRows }){
  const matchById = new Map(matches.map(m => [m.id, m]));
  const kitMissingKeys = new Set(kitRows.map(k => `${k.match_id}:${k.player.id}`));

  const eventsByTeam = new Map(teams.map(t => [t.id, []]));

  for(const m of matches){
    const week = m.week?.week_number;
    for(const [teamId, stake, oppStake] of [
      [m.team_a_id, m.team_a_stake, m.team_b_stake],
      [m.team_b_id, m.team_b_stake, m.team_a_stake],
    ]){
      if(!eventsByTeam.has(teamId)) continue;
      const won = m.winner_team_id === teamId;
      eventsByTeam.get(teamId).push({
        when: m.confirmed_at, week, kind: "main",
        desc: won ? `فاز الفريق` : `خسر الفريق`,
        delta: won ? stake : -stake,
      });
    }
  }

  for(const l of loans){
    const week = matchById.get(l.match_id)?.week?.week_number;
    const kitMissing = kitMissingKeys.has(`${l.match_id}:${l.player_id}`);
    const fee = kitMissing ? Math.ceil(l.winning_bid_amount / 2) : l.winning_bid_amount;
    const player = l.player?.full_name || "لاعب";
    const kitNote = kitMissing ? " (لم يحضر بدلته)" : "";

    if(eventsByTeam.has(l.borrowing_team_id)){
      eventsByTeam.get(l.borrowing_team_id).push({
        when: matchById.get(l.match_id)?.confirmed_at, week, kind: "main",
        desc: `استعارة "${player}"${kitNote}`,
        delta: -fee,
      });
    }
    if(eventsByTeam.has(l.original_team_id)){
      const borrowerName = teams.find(t => t.id === l.borrowing_team_id)?.name || "فريق آخر";
      eventsByTeam.get(l.original_team_id).push({
        when: matchById.get(l.match_id)?.confirmed_at, week, kind: "credit",
        desc: `فريق ${borrowerName} استعار "${player}"${kitNote}`,
        delta: fee,
      });
    }
  }

  for(const k of kitRows){
    if(k.player.original_team_id !== k.team_id) continue; // بس اللاعبين الأصليين (مو المعارين)
    if(!eventsByTeam.has(k.team_id)) continue;
    const week = matchById.get(k.match_id)?.week?.week_number;
    eventsByTeam.get(k.team_id).push({
      when: matchById.get(k.match_id)?.confirmed_at, week, kind: "main",
      desc: `"${k.player.full_name}" بدون بدلة`,
      delta: -40,
    });
  }

  for(const t of teams){
    const events = eventsByTeam.get(t.id) || [];
    events.sort((a, b) => (a.when || "").localeCompare(b.when || ""));
    const totalDelta = events.reduce((s, e) => s + e.delta, 0);
    let running = t.balance_wathaq - totalDelta;
    for(const e of events){
      running += e.delta;
      e.balanceAfter = running;
    }
  }

  return eventsByTeam;
}
