const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;

before(async function () {
  this.timeout(30000);
  testEnv = await initializeTestEnvironment({
    projectId: "inspectra-firestore-rules-test",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seedProfile(uid, role) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("profiles").doc(uid).set({ role });
  });
}

describe("profiles", () => {
  it("lets a signed-in user create their own profile as officer", async () => {
    const db = testEnv.authenticatedContext("u1").firestore();
    await assertSucceeds(
      db.collection("profiles").doc("u1").set({ role: "officer" })
    );
  });

  it("denies self-creating a profile with role admin", async () => {
    const db = testEnv.authenticatedContext("u1").firestore();
    await assertFails(
      db.collection("profiles").doc("u1").set({ role: "admin" })
    );
  });

  it("denies creating a profile doc for a different uid", async () => {
    const db = testEnv.authenticatedContext("u1").firestore();
    await assertFails(
      db.collection("profiles").doc("someone-else").set({ role: "officer" })
    );
  });

  it("lets a user read their own profile", async () => {
    await seedProfile("u1", "officer");
    const db = testEnv.authenticatedContext("u1").firestore();
    await assertSucceeds(db.collection("profiles").doc("u1").get());
  });

  it("denies a non-admin reading someone else's profile", async () => {
    await seedProfile("u1", "officer");
    await seedProfile("u2", "officer");
    const db = testEnv.authenticatedContext("u2").firestore();
    await assertFails(db.collection("profiles").doc("u1").get());
  });

  it("lets an admin read any profile", async () => {
    await seedProfile("u1", "officer");
    await seedProfile("adminUser", "admin");
    const db = testEnv.authenticatedContext("adminUser").firestore();
    await assertSucceeds(db.collection("profiles").doc("u1").get());
  });

  it("denies a non-admin updating another user's profile (self-escalation)", async () => {
    await seedProfile("u1", "officer");
    const db = testEnv.authenticatedContext("u1").firestore();
    await assertFails(
      db.collection("profiles").doc("u1").update({ role: "admin" })
    );
  });

  it("lets an admin update a user's profile (e.g. promote to admin)", async () => {
    await seedProfile("u1", "officer");
    await seedProfile("adminUser", "admin");
    const db = testEnv.authenticatedContext("adminUser").firestore();
    await assertSucceeds(
      db.collection("profiles").doc("u1").update({ role: "admin" })
    );
  });
});

describe("establishments (role-gated collection)", () => {
  it("denies unauthenticated reads", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection("establishments").doc("e1").get());
  });

  it("denies reads from a signed-in user with no profile doc", async () => {
    const db = testEnv.authenticatedContext("noProfile").firestore();
    await assertFails(db.collection("establishments").doc("e1").get());
  });

  it("lets an officer read and write establishments", async () => {
    await seedProfile("officer1", "officer");
    const db = testEnv.authenticatedContext("officer1").firestore();
    await assertSucceeds(
      db.collection("establishments").doc("e1").set({ name: "Test" })
    );
    await assertSucceeds(db.collection("establishments").doc("e1").get());
  });

  it("denies an officer deleting an establishment (admin-only)", async () => {
    await seedProfile("officer1", "officer");
    await seedProfile("adminUser", "admin");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("establishments").doc("e1").set({ name: "Test" });
    });
    const db = testEnv.authenticatedContext("officer1").firestore();
    await assertFails(db.collection("establishments").doc("e1").delete());
  });

  it("lets an admin delete an establishment", async () => {
    await seedProfile("adminUser", "admin");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("establishments").doc("e1").set({ name: "Test" });
    });
    const db = testEnv.authenticatedContext("adminUser").firestore();
    await assertSucceeds(db.collection("establishments").doc("e1").delete());
  });
});

describe("permit history sub-collection (mirrors establishments)", () => {
  it("lets an officer read and write a permit doc under an establishment", async () => {
    await seedProfile("officer1", "officer");
    const db = testEnv.authenticatedContext("officer1").firestore();
    const permitRef = db
      .collection("establishments").doc("e1")
      .collection("permits").doc("F-261174");
    await assertSucceeds(permitRef.set({ permit_no: "F-261174" }));
    await assertSucceeds(permitRef.get());
  });

  it("denies an officer deleting a permit doc (admin-only)", async () => {
    await seedProfile("officer1", "officer");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore()
        .collection("establishments").doc("e1")
        .collection("permits").doc("F-261174").set({ permit_no: "F-261174" });
    });
    const db = testEnv.authenticatedContext("officer1").firestore();
    await assertFails(
      db.collection("establishments").doc("e1")
        .collection("permits").doc("F-261174").delete()
    );
  });
});

describe("masterlist import machinery (admin-only)", () => {
  it("lets an admin create and read an upload batch", async () => {
    await seedProfile("adminUser", "admin");
    const db = testEnv.authenticatedContext("adminUser").firestore();
    await assertSucceeds(
      db.collection("upload_batches").doc("b1").set({ status: "running" })
    );
    await assertSucceeds(db.collection("upload_batches").doc("b1").get());
  });

  it("denies an officer reading or writing upload batches", async () => {
    await seedProfile("officer1", "officer");
    const db = testEnv.authenticatedContext("officer1").firestore();
    await assertFails(
      db.collection("upload_batches").doc("b1").set({ status: "running" })
    );
    await assertFails(db.collection("upload_batches").doc("b1").get());
  });

  it("denies even an admin deleting an upload batch (audit record)", async () => {
    await seedProfile("adminUser", "admin");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("upload_batches").doc("b1").set({ status: "done" });
    });
    const db = testEnv.authenticatedContext("adminUser").firestore();
    await assertFails(db.collection("upload_batches").doc("b1").delete());
  });

  it("lets an admin manage the review queue but denies officers", async () => {
    await seedProfile("adminUser", "admin");
    await seedProfile("officer1", "officer");
    const adminDb = testEnv.authenticatedContext("adminUser").firestore();
    const officerDb = testEnv.authenticatedContext("officer1").firestore();
    await assertSucceeds(
      adminDb.collection("review_queue").doc("r1").set({ status: "pending" })
    );
    await assertFails(officerDb.collection("review_queue").doc("r1").get());
    await assertFails(
      officerDb.collection("review_queue").doc("r2").set({ status: "pending" })
    );
  });
});

describe("reference data (admin-write-only)", () => {
  it("lets an officer read categories but not write them", async () => {
    await seedProfile("officer1", "officer");
    const db = testEnv.authenticatedContext("officer1").firestore();
    await assertSucceeds(db.collection("categories").doc("c1").get());
    await assertFails(
      db.collection("categories").doc("c1").set({ name: "Test" })
    );
  });

  it("lets an admin write categories", async () => {
    await seedProfile("adminUser", "admin");
    const db = testEnv.authenticatedContext("adminUser").firestore();
    await assertSucceeds(
      db.collection("categories").doc("c1").set({ name: "Test" })
    );
  });
});
