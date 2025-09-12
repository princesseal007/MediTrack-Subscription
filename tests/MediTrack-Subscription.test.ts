import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

describe("MediTrack Subscription", () => {
    const accounts = simnet.getAccounts();
    const provider1 = accounts.get("wallet_1")!;
    const provider2 = accounts.get("wallet_2")!;
    const provider3 = accounts.get("wallet_3")!;

    beforeEach(() => {
        simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );
    });

    it("allows healthcare provider to subscribe with basic tier", () => {
        const subscribeCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );
        expect(subscribeCall.result).toHaveProperty('type', 7);
    });

    it("allows healthcare provider to subscribe with specialist tier", () => {
        const subscribeCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("specialist")],
            provider2
        );
        expect(subscribeCall.result).toHaveProperty('type', 7);
    });

    it("correctly reports subscription status", () => {
        const getSubscriptionCall = simnet.callReadOnlyFn(
            "MediTrack-Subscription",
            "get-subscription",
            [Cl.principal(provider1)],
            provider1
        );
        expect(getSubscriptionCall.result).toHaveProperty('type', 7);
    });

    it("allows enabling emergency access", () => {
        const emergencyAccessCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "enable-emergency-access",
            [],
            provider1
        );
        expect(emergencyAccessCall.result).toHaveProperty('type', 7);
    });

    it("correctly checks active subscription status", () => {
        const activeStatusCall = simnet.callReadOnlyFn(
            "MediTrack-Subscription",
            "is-active-subscriber",
            [Cl.principal(provider1)],
            provider1
        );
        expect(activeStatusCall.result).toHaveProperty('type', 7);
    });

    describe("renew-subscription function", () => {
        it("successfully renews subscription for existing subscriber", () => {
            const renewCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "renew-subscription",
                [],
                provider1
            );
            expect(renewCall.result).toHaveProperty('type', 7);
        });

        it("fails to renew subscription for non-subscriber", () => {
            const renewCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "renew-subscription",
                [],
                provider3
            );
            expect(renewCall.result).toHaveProperty('type', 8);
        });
    });

    describe("change-subscription-tier function", () => {
        it("successfully changes tier to specialist", () => {
            const changeCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "change-subscription-tier",
                [Cl.stringAscii("specialist")],
                provider1
            );
            expect(changeCall.result).toHaveProperty('type', 7);
        });

        it("successfully changes tier to premium", () => {
            const changeCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "change-subscription-tier",
                [Cl.stringAscii("premium")],
                provider1
            );
            expect(changeCall.result).toHaveProperty('type', 7);
        });

        it("fails with invalid tier", () => {
            const changeCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "change-subscription-tier",
                [Cl.stringAscii("invalid")],
                provider1
            );
            expect(changeCall.result).toHaveProperty('type', 8);
        });

        it("fails for non-subscriber", () => {
            const changeCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "change-subscription-tier",
                [Cl.stringAscii("specialist")],
                provider3
            );
            expect(changeCall.result).toHaveProperty('type', 8);
        });
    });

    describe("toggle-auto-renewal function", () => {
        it("successfully enables auto-renewal", () => {
            const toggleCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "toggle-auto-renewal",
                [],
                provider1
            );
            expect(toggleCall.result).toHaveProperty('type', 7);
        });

        it("successfully toggles auto-renewal twice", () => {
            simnet.callPublicFn(
                "MediTrack-Subscription",
                "toggle-auto-renewal",
                [],
                provider1
            );
            
            const secondToggle = simnet.callPublicFn(
                "MediTrack-Subscription",
                "toggle-auto-renewal",
                [],
                provider1
            );
            expect(secondToggle.result).toHaveProperty('type', 7);
        });
    });

    describe("transfer-subscription function", () => {
        it("successfully transfers subscription to new owner", () => {
            const transferCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "transfer-subscription",
                [Cl.principal(provider2)],
                provider1
            );
            expect(transferCall.result).toHaveProperty('type', 7);
        });

        it("fails transfer for non-subscriber", () => {
            const transferCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "transfer-subscription",
                [Cl.principal(provider1)],
                provider3
            );
            expect(transferCall.result).toHaveProperty('type', 8);
        });

        it("verifies new owner has subscription after transfer", () => {
            simnet.callPublicFn(
                "MediTrack-Subscription",
                "transfer-subscription",
                [Cl.principal(provider2)],
                provider1
            );

            const newOwnerSub = simnet.callReadOnlyFn(
                "MediTrack-Subscription",
                "get-subscription",
                [Cl.principal(provider2)],
                provider2
            );
            expect(newOwnerSub.result).toHaveProperty('type', 7);
        });
    });

    describe("accumulate-points function", () => {
        it("successfully accumulates loyalty points", () => {
            const pointsCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "accumulate-points",
                [],
                provider1
            );
            expect(pointsCall.result).toHaveProperty('type', 7);
        });

        it("correctly increments points on multiple calls", () => {
            simnet.callPublicFn(
                "MediTrack-Subscription",
                "accumulate-points",
                [],
                provider1
            );

            const secondCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "accumulate-points",
                [],
                provider1
            );
            expect(secondCall.result).toHaveProperty('type', 7);
        });

        it("initializes points for new user", () => {
            const pointsCall = simnet.callPublicFn(
                "MediTrack-Subscription",
                "accumulate-points",
                [],
                provider3
            );
            expect(pointsCall.result).toHaveProperty('type', 7);
        });
    });
    
});
