interface LadderReceiptLike { backend: string; verdict: string; evidence: Record<string, unknown> }

export interface TheoryLadderStep { level: 'catalog' | 'heuristic-cegis' | 'cvc5-sygus' | 'formal-promotion'; status: 'miss' | 'candidate' | 'proved' | 'absent' | 'unknown' | 'blocked'; evidence: string }

export function buildTheoryLadder(input: { receipts: LadderReceiptLike[]; trainPassed: number; trainTotal: number; heldOutPassed: number; heldOutTotal: number; promotionEligible: boolean }): TheoryLadderStep[] {
  const cvc5 = input.receipts.find((receipt) => receipt.backend === 'cvc5-sygus');
  const heuristic = input.receipts.find((receipt) => receipt.backend === 'heuristic');
  return [
    { level: 'catalog', status: 'miss', evidence: 'no pre-existing catalog operator is credited for this unseen island' },
    { level: 'heuristic-cegis', status: heuristic ? 'candidate' : 'miss', evidence: 'train ' + input.trainPassed + '/' + input.trainTotal + ', held-out ' + input.heldOutPassed + '/' + input.heldOutTotal + '; heuristic receipts are not promotion eligible' },
    { level: 'cvc5-sygus', status: cvc5?.verdict === 'PROVEN' ? 'proved' : cvc5?.verdict === 'ABSENT' ? 'absent' : cvc5 ? 'unknown' : 'blocked', evidence: cvc5 ? String(cvc5.evidence.reason ?? cvc5.verdict) : 'cvc5 backend not requested' },
    { level: 'formal-promotion', status: input.promotionEligible ? 'proved' : 'blocked', evidence: input.promotionEligible ? 'at least one formal PROVEN receipt verified' : 'no verified formal PROVEN receipt; generated operator remains preview-only' },
  ];
}
