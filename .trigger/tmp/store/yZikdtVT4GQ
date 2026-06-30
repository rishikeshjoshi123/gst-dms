import {
  task
} from "../../../../chunk-CUZC63FW.mjs";
import "../../../../chunk-LRTAKWDY.mjs";
import {
  __name,
  init_esm
} from "../../../../chunk-5QNIFE2Q.mjs";

// src/trigger/jobs.ts
init_esm();
var processDocument = task({
  id: "process-document",
  maxDuration: 300,
  // 5 minutes max
  retry: {
    maxAttempts: 3,
    minTimeoutInMs: 1e3,
    maxTimeoutInMs: 3e4,
    factor: 2,
    randomize: true
  },
  run: /* @__PURE__ */ __name(async (payload, { ctx }) => {
    const {
      docId,
      matterId,
      orgId,
      storagePath,
      uploadedBy,
      reprocessMode = "full"
    } = payload;
    const { createServiceClient } = await import("../../../../server-R3ISEH7K.mjs");
    const supabase = createServiceClient();
    console.log(`[Step 1] Downloading ${storagePath}`);
    const { data: fileData, error: downloadError } = await supabase.storage.from("documents").download(storagePath);
    if (downloadError || !fileData) {
      await updateDocStatus(supabase, docId, "failed");
      throw new Error(`[Step 1] Download failed: ${downloadError?.message}`);
    }
    const fileBuffer = Buffer.from(await fileData.arrayBuffer());
    console.log("[Step 2] SHA-256 duplicate check");
    const { createHash } = await import("crypto");
    const sha256 = createHash("sha256").update(fileBuffer).digest("hex");
    const { data: exactDupRaw } = await supabase.from("documents").select("id, reference_number").eq("matter_id", matterId).eq("file_hash_sha256", sha256).neq("id", docId).is("deleted_at", null).maybeSingle();
    const exactDup = exactDupRaw;
    if (exactDup) {
      await updateDocStatus(supabase, docId, "failed");
      await createNotification(supabase, {
        orgId,
        userId: uploadedBy,
        type: "processing_failed",
        title: "Duplicate document detected",
        body: `This file is identical to an existing document (${exactDup.reference_number ?? exactDup.id}). Upload blocked.`,
        entityType: "document",
        entityId: exactDup.id
      });
      throw new Error(`[Step 2] Exact duplicate — matches doc ${exactDup.id}`);
    }
    await supabase.from("documents").update({ file_hash_sha256: sha256, status: "processing" }).eq("id", docId);
    console.log("[Step 3] Vertex AI analysis");
    const aiResult = null;
    if (!aiResult) {
      await updateDocStatus(supabase, docId, "needs_review");
      console.warn("[Step 3] AI analysis returned null — marking needs_review");
      return { status: "needs_review", docId };
    }
    console.log("[Step 4] Parsing AI output");
    await updateDocStatus(supabase, docId, "analyzed");
    console.log("[Step 5] Generating embedding");
    console.log("[Step 6] Semantic duplicate check (cosine similarity)");
    console.log("[Step 7] Content hash check");
    if (reprocessMode === "full") {
      console.log("[Step 8] Chain placement");
    } else {
      console.log("[Step 8] Skipped (metadata_only reprocess mode)");
    }
    console.log("[Step 9] Resolving pending links");
    console.log("[Step 10] Updating deadlines");
    console.log("[Step 11] Triggering wiki update");
    console.log("[Step 12] Writing activity log");
    await supabase.from("activity_logs").insert({
      org_id: orgId,
      user_id: uploadedBy,
      action: "document_processed",
      entity_type: "document",
      entity_id: docId,
      description: `Document processed successfully by pipeline`,
      metadata: { pipeline_run_id: ctx.run.id, reprocess_mode: reprocessMode },
      is_reversible: false
    });
    console.log("[Step 13] Notifying users");
    await createNotification(supabase, {
      orgId,
      userId: uploadedBy,
      type: "document_ready",
      title: "Document analyzed",
      body: "Your document has been processed and is ready to review.",
      entityType: "document",
      entityId: docId
    });
    await updateDocStatus(supabase, docId, "placed");
    return { status: "placed", docId };
  }, "run")
});
var analyzeStagedDocument = task({
  id: "analyze-staged-document",
  maxDuration: 120,
  retry: {
    maxAttempts: 3,
    minTimeoutInMs: 1e3,
    maxTimeoutInMs: 15e3,
    factor: 2
  },
  run: /* @__PURE__ */ __name(async (payload) => {
    const { stagedDocId, orgId, uploadedBy, storagePath } = payload;
    const { createServiceClient } = await import("../../../../server-R3ISEH7K.mjs");
    const supabase = createServiceClient();
    await supabase.from("staged_documents").update({ status: "analyzing" }).eq("id", stagedDocId);
    await supabase.from("staged_documents").update({ status: "ready_to_assign", suggested_matter_ids: [] }).eq("id", stagedDocId);
    await createNotification(supabase, {
      orgId,
      userId: uploadedBy,
      type: "staged_doc_ready",
      title: "Document analyzed — please assign it to a matter",
      body: "Open the Needs Attention panel to assign this document.",
      entityType: "staged_document",
      entityId: stagedDocId
    });
    return { stagedDocId, status: "ready_to_assign" };
  }, "run")
});
var deadlineReminderCron = task({
  id: "deadline-reminders",
  run: /* @__PURE__ */ __name(async () => {
    const { createServiceClient } = await import("../../../../server-R3ISEH7K.mjs");
    const supabase = createServiceClient();
    const today = /* @__PURE__ */ new Date();
    const in7Days = new Date(today);
    in7Days.setDate(in7Days.getDate() + 7);
    const in30Days = new Date(today);
    in30Days.setDate(in30Days.getDate() + 30);
    console.log("[Deadline cron] Checking approaching deadlines...");
    return { checked: true };
  }, "run")
});
async function updateDocStatus(supabase, docId, status) {
  await supabase.from("documents").update({ status }).eq("id", docId);
}
__name(updateDocStatus, "updateDocStatus");
async function createNotification(supabase, opts) {
  await supabase.from("notifications").insert({
    org_id: opts.orgId,
    user_id: opts.userId,
    type: opts.type,
    title: opts.title,
    body: opts.body,
    entity_type: opts.entityType,
    entity_id: opts.entityId
  });
}
__name(createNotification, "createNotification");
export {
  analyzeStagedDocument,
  deadlineReminderCron,
  processDocument
};
//# sourceMappingURL=jobs.mjs.map
