export const atomicIntentContract = {
  goal: "Add chat persistence feature",
  actor: "user",
  targetIntegration: "chat_persistence",
  integrationLabel: "Chat persistido em Postgres",
  riskLevel: "normal",
  surfaces: ["backend service/controller","Prisma/Postgres","frontend-admin chat UI","chat tests"],
  acceptanceCriteria: ["Messages are saved to database"],
  validationPlan: ["Test that messages persist after page reload"],
} as const;

export function describeAtomicIntentContract(): string {
  return atomicIntentContract.goal;
}
