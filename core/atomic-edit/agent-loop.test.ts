import { describe, it, expect } from 'vitest';
import {
  createSession,
  recordEntry,
  advancePhase,
  nextStep,
  accept,
  requestRevision,
  proposalsForStep,
  AgentPhase,
  incrementAttempt,
} from './agent-loop.js';

describe('agent-loop', () => {
  describe('createSession', () => {
    it('initializes with plan phase', () => {
      const session = createSession('test issue', [
        { step: 1, description: 'Investigate', expectedOutcome: 'Found' },
      ]);
      expect(session.phase).toBe(AgentPhase.PLAN);
      expect(session.plan.issue).toBe('test issue');
      expect(session.plan.steps).toHaveLength(1);
    });

    it('assigns unique session ID', () => {
      const s1 = createSession('a', []);
      const s2 = createSession('b', []);
      expect(s1.sessionId).not.toBe(s2.sessionId);
    });
  });

  describe('advancePhase', () => {
    it('advances through initial phases', () => {
      const session = createSession('issue', [
        { step: 1, description: 'A', expectedOutcome: 'OK' },
      ]);
      expect(session.phase).toBe(AgentPhase.PLAN);
      advancePhase(session);
      expect(session.phase).toBe(AgentPhase.INVESTIGATE);
    });
  });

  describe('nextStep', () => {
    it('returns first incomplete step', () => {
      const session = createSession('issue', [
        { step: 1, description: 'A', expectedOutcome: 'OK' },
        { step: 2, description: 'B', expectedOutcome: 'OK' },
      ]);
      advancePhase(session);
      expect(typeof nextStep(session)).toBe('number');
    });

    it('returns null when all steps completed', () => {
      const session = createSession('issue', [
        { step: 1, description: 'A', expectedOutcome: 'OK' },
      ]);
      advancePhase(session);
      recordEntry(session, {
        step: 1,
        tool: 'read',
        findings: ['done'],
        at: Date.now(),
      });
      expect(nextStep(session)).toBe(null);
    });
  });

  describe('accept / requestRevision', () => {
    it('accept records a decision', () => {
      const session = createSession('issue', [
        { step: 1, description: 'A', expectedOutcome: 'OK' },
      ]);
      const decision = accept(session, {}, 'looks good');
      expect(decision.verdict).toBe('accepted');
    });

    it('requestRevision records a needs_revision', () => {
      const session = createSession('issue', [
        { step: 1, description: 'A', expectedOutcome: 'OK' },
      ]);
      const decision = requestRevision(session, 'try again', 'needs work');
      expect(decision.verdict).toBe('needs_revision');
    });
  });

  describe('proposalsForStep', () => {
    it('returns empty for no proposals', () => {
      const session = createSession('issue', [
        { step: 1, description: 'A', expectedOutcome: 'OK' },
      ]);
      expect(proposalsForStep(session, 1)).toHaveLength(0);
    });
  });

  describe('adaptive budget', () => {
    it('calculates initial maxAttempts based on complexity', () => {
      const sLow = createSession('issue', [{ step: 1, description: 'A', expectedOutcome: 'OK' }]);
      expect(sLow.maxAttempts).toBe(3);

      const sMedium = createSession('issue', [
        { step: 1, description: 'A', expectedOutcome: 'OK' },
        { step: 2, description: 'B', expectedOutcome: 'OK' },
        { step: 3, description: 'C', expectedOutcome: 'OK' },
        { step: 4, description: 'D', expectedOutcome: 'OK' },
      ]);
      expect(sMedium.maxAttempts).toBe(5);

      const sHigh = createSession('issue', Array(8).fill({ step: 1, description: 'A', expectedOutcome: 'OK' }));
      expect(sHigh.maxAttempts).toBe(8);

      const sCritical = createSession('issue', Array(12).fill({ step: 1, description: 'A', expectedOutcome: 'OK' }));
      expect(sCritical.maxAttempts).toBe(12);
    });

    it('grants adaptive maxAttempts bonus on test progress near exhaustion limit', () => {
      const session = createSession('issue', [{ step: 1, description: 'A', expectedOutcome: 'OK' }]);
      session.maxAttempts = 1;
      session.attemptCount = 1;

      // 1ª Decisão (mal sucedida)
      recordEntry(session, {
        verdict: 'needs_revision',
        reason: 'fail',
        detail: 'fail',
        evidence: { testResults: '2 failed, 10 passed' }
      });

      // 2ª Decisão (mostra progresso)
      recordEntry(session, {
        verdict: 'needs_revision',
        reason: 'fail',
        detail: 'fail',
        evidence: { testResults: '1 failed, 11 passed' }
      });

      const before = session.maxAttempts;
      const ok = incrementAttempt(session);

      expect(session.maxAttempts).toBe(before + 1);
      expect(ok).toBe(true);
    });
  });
});
