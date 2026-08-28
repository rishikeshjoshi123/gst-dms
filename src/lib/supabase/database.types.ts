export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      activity_logs: {
        Row: {
          action: string
          created_at: string
          description: string | null
          entity_id: string | null
          entity_type: Database["public"]["Enums"]["entity_type"]
          id: string
          is_reversible: boolean
          metadata: Json | null
          org_id: string
          reversed_at: string | null
          reversed_by: string | null
          user_id: string | null
        }
        Insert: {
          action: string
          created_at?: string
          description?: string | null
          entity_id?: string | null
          entity_type: Database["public"]["Enums"]["entity_type"]
          id?: string
          is_reversible?: boolean
          metadata?: Json | null
          org_id: string
          reversed_at?: string | null
          reversed_by?: string | null
          user_id?: string | null
        }
        Update: {
          action?: string
          created_at?: string
          description?: string | null
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"]
          id?: string
          is_reversible?: boolean
          metadata?: Json | null
          org_id?: string
          reversed_at?: string | null
          reversed_by?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activity_logs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      administration_events: {
        Row: {
          actor_user_id: string | null
          correlation_id: string
          created_at: string
          event_kind: string
          id: string
          idempotency_key: string | null
          metadata: Json
          org_id: string
          reason: string | null
          target_snapshot: Json
          target_user_id: string | null
        }
        Insert: {
          actor_user_id?: string | null
          correlation_id: string
          created_at?: string
          event_kind: string
          id?: string
          idempotency_key?: string | null
          metadata?: Json
          org_id: string
          reason?: string | null
          target_snapshot?: Json
          target_user_id?: string | null
        }
        Update: {
          actor_user_id?: string | null
          correlation_id?: string
          created_at?: string
          event_kind?: string
          id?: string
          idempotency_key?: string | null
          metadata?: Json
          org_id?: string
          reason?: string | null
          target_snapshot?: Json
          target_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "administration_events_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_usage_logs: {
        Row: {
          created_at: string
          document_id: string | null
          id: string
          input_tokens: number
          metadata: Json | null
          model_name: string
          operation_type: string
          org_id: string
          output_tokens: number
          total_cost_usd: number
          user_id: string | null
        }
        Insert: {
          created_at?: string
          document_id?: string | null
          id?: string
          input_tokens?: number
          metadata?: Json | null
          model_name: string
          operation_type: string
          org_id: string
          output_tokens?: number
          total_cost_usd?: number
          user_id?: string | null
        }
        Update: {
          created_at?: string
          document_id?: string | null
          id?: string
          input_tokens?: number
          metadata?: Json | null
          model_name?: string
          operation_type?: string
          org_id?: string
          output_tokens?: number
          total_cost_usd?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_usage_logs_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_usage_logs_model_name_fkey"
            columns: ["model_name"]
            isOneToOne: false
            referencedRelation: "model_pricing"
            referencedColumns: ["model_name"]
          },
          {
            foreignKeyName: "ai_usage_logs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      case_notes: {
        Row: {
          action_item_assignee: string | null
          action_item_due_date: string | null
          action_item_resolved: boolean
          author_id: string
          content: string
          created_at: string
          deleted_at: string | null
          document_id: string | null
          id: string
          is_action_item: boolean
          is_pinned: boolean
          matter_id: string
          org_id: string
          page_number: number | null
          parent_note_id: string | null
          quote: string | null
          search_vector: unknown
          template_type: Database["public"]["Enums"]["note_template_type"]
          updated_at: string
        }
        Insert: {
          action_item_assignee?: string | null
          action_item_due_date?: string | null
          action_item_resolved?: boolean
          author_id: string
          content: string
          created_at?: string
          deleted_at?: string | null
          document_id?: string | null
          id?: string
          is_action_item?: boolean
          is_pinned?: boolean
          matter_id: string
          org_id: string
          page_number?: number | null
          parent_note_id?: string | null
          quote?: string | null
          search_vector?: unknown
          template_type?: Database["public"]["Enums"]["note_template_type"]
          updated_at?: string
        }
        Update: {
          action_item_assignee?: string | null
          action_item_due_date?: string | null
          action_item_resolved?: boolean
          author_id?: string
          content?: string
          created_at?: string
          deleted_at?: string | null
          document_id?: string | null
          id?: string
          is_action_item?: boolean
          is_pinned?: boolean
          matter_id?: string
          org_id?: string
          page_number?: number | null
          parent_note_id?: string | null
          quote?: string | null
          search_vector?: unknown
          template_type?: Database["public"]["Enums"]["note_template_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "case_notes_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "case_notes_matter_id_fkey"
            columns: ["matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "case_notes_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "case_notes_parent_note_id_fkey"
            columns: ["parent_note_id"]
            isOneToOne: false
            referencedRelation: "case_notes"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          company_name: string | null
          contact_info: Json | null
          created_at: string
          deleted_at: string | null
          gstin: string | null
          id: string
          name: string
          org_id: string
          pan: string | null
          updated_at: string
        }
        Insert: {
          company_name?: string | null
          contact_info?: Json | null
          created_at?: string
          deleted_at?: string | null
          gstin?: string | null
          id?: string
          name: string
          org_id: string
          pan?: string | null
          updated_at?: string
        }
        Update: {
          company_name?: string | null
          contact_info?: Json | null
          created_at?: string
          deleted_at?: string | null
          gstin?: string | null
          id?: string
          name?: string
          org_id?: string
          pan?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clients_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      deadlines: {
        Row: {
          created_at: string
          description: string | null
          document_id: string | null
          due_date: string
          id: string
          is_resolved: boolean
          matter_id: string
          reminder_sent_30d: boolean
          reminder_sent_7d: boolean
          resolved_at: string | null
          resolved_by: string | null
          type: Database["public"]["Enums"]["deadline_type"]
        }
        Insert: {
          created_at?: string
          description?: string | null
          document_id?: string | null
          due_date: string
          id?: string
          is_resolved?: boolean
          matter_id: string
          reminder_sent_30d?: boolean
          reminder_sent_7d?: boolean
          resolved_at?: string | null
          resolved_by?: string | null
          type: Database["public"]["Enums"]["deadline_type"]
        }
        Update: {
          created_at?: string
          description?: string | null
          document_id?: string | null
          due_date?: string
          id?: string
          is_resolved?: boolean
          matter_id?: string
          reminder_sent_30d?: boolean
          reminder_sent_7d?: boolean
          resolved_at?: string | null
          resolved_by?: string | null
          type?: Database["public"]["Enums"]["deadline_type"]
        }
        Relationships: [
          {
            foreignKeyName: "deadlines_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deadlines_matter_id_fkey"
            columns: ["matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["id"]
          },
        ]
      }
      document_command_receipts: {
        Row: {
          actor_user_id: string | null
          command_kind: string
          created_at: string
          document_id: string | null
          document_version_id: string | null
          id: string
          idempotency_key: string
          lifecycle_revision: number | null
          org_id: string
          result_code: string
          subject_id: string
        }
        Insert: {
          actor_user_id?: string | null
          command_kind: string
          created_at?: string
          document_id?: string | null
          document_version_id?: string | null
          id?: string
          idempotency_key: string
          lifecycle_revision?: number | null
          org_id: string
          result_code: string
          subject_id: string
        }
        Update: {
          actor_user_id?: string | null
          command_kind?: string
          created_at?: string
          document_id?: string | null
          document_version_id?: string | null
          id?: string
          idempotency_key?: string
          lifecycle_revision?: number | null
          org_id?: string
          result_code?: string
          subject_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_command_receipts_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_command_receipts_document_version_id_fkey"
            columns: ["document_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_command_receipts_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      document_links: {
        Row: {
          confidence: number | null
          created_at: string
          created_by: string | null
          from_doc_id: string
          id: string
          link_type: Database["public"]["Enums"]["link_type"]
          match_method: string | null
          pending_ref_number: string | null
          status: Database["public"]["Enums"]["link_status"]
          to_doc_id: string | null
        }
        Insert: {
          confidence?: number | null
          created_at?: string
          created_by?: string | null
          from_doc_id: string
          id?: string
          link_type: Database["public"]["Enums"]["link_type"]
          match_method?: string | null
          pending_ref_number?: string | null
          status?: Database["public"]["Enums"]["link_status"]
          to_doc_id?: string | null
        }
        Update: {
          confidence?: number | null
          created_at?: string
          created_by?: string | null
          from_doc_id?: string
          id?: string
          link_type?: Database["public"]["Enums"]["link_type"]
          match_method?: string | null
          pending_ref_number?: string | null
          status?: Database["public"]["Enums"]["link_status"]
          to_doc_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "document_links_from_doc_id_fkey"
            columns: ["from_doc_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_links_to_doc_id_fkey"
            columns: ["to_doc_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
        ]
      }
      document_processing_runs: {
        Row: {
          attempt_count: number
          completed_at: string | null
          created_at: string
          document_id: string
          document_version_id: string
          failed_at: string | null
          heartbeat_at: string | null
          id: string
          idempotency_key: string
          lease_expires_at: string | null
          lease_token: string | null
          org_id: string
          outbox_event_id: string | null
          safe_error_code: string | null
          scope: Database["public"]["Enums"]["document_processing_scope"]
          source_analysis_run_id: string | null
          stage: Database["public"]["Enums"]["document_processing_stage"]
          started_at: string | null
          state: Database["public"]["Enums"]["document_processing_state"]
          trigger_run_id: string | null
        }
        Insert: {
          attempt_count?: number
          completed_at?: string | null
          created_at?: string
          document_id: string
          document_version_id: string
          failed_at?: string | null
          heartbeat_at?: string | null
          id?: string
          idempotency_key: string
          lease_expires_at?: string | null
          lease_token?: string | null
          org_id: string
          outbox_event_id?: string | null
          safe_error_code?: string | null
          scope: Database["public"]["Enums"]["document_processing_scope"]
          source_analysis_run_id?: string | null
          stage?: Database["public"]["Enums"]["document_processing_stage"]
          started_at?: string | null
          state?: Database["public"]["Enums"]["document_processing_state"]
          trigger_run_id?: string | null
        }
        Update: {
          attempt_count?: number
          completed_at?: string | null
          created_at?: string
          document_id?: string
          document_version_id?: string
          failed_at?: string | null
          heartbeat_at?: string | null
          id?: string
          idempotency_key?: string
          lease_expires_at?: string | null
          lease_token?: string | null
          org_id?: string
          outbox_event_id?: string | null
          safe_error_code?: string | null
          scope?: Database["public"]["Enums"]["document_processing_scope"]
          source_analysis_run_id?: string | null
          stage?: Database["public"]["Enums"]["document_processing_stage"]
          started_at?: string | null
          state?: Database["public"]["Enums"]["document_processing_state"]
          trigger_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "document_processing_runs_document_org_fkey"
            columns: ["org_id", "document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "document_processing_runs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_processing_runs_outbox_event_id_fkey"
            columns: ["outbox_event_id"]
            isOneToOne: true
            referencedRelation: "outbox_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_processing_runs_source_org_fkey"
            columns: ["org_id", "source_analysis_run_id"]
            isOneToOne: false
            referencedRelation: "source_analysis_runs"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "document_processing_runs_version_org_fkey"
            columns: ["org_id", "document_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      document_upload_command_receipts: {
        Row: {
          code: string
          command: string
          created_at: string
          duplicate_asset_id: string | null
          id: string
          idempotency_key: string
          org_id: string
          upload_session_id: string
        }
        Insert: {
          code: string
          command: string
          created_at?: string
          duplicate_asset_id?: string | null
          id?: string
          idempotency_key: string
          org_id: string
          upload_session_id: string
        }
        Update: {
          code?: string
          command?: string
          created_at?: string
          duplicate_asset_id?: string | null
          id?: string
          idempotency_key?: string
          org_id?: string
          upload_session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_upload_command_receipts_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_upload_command_receipts_upload_session_id_fkey"
            columns: ["upload_session_id"]
            isOneToOne: false
            referencedRelation: "upload_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      document_version_analysis_bindings: {
        Row: {
          binding_reason: string
          created_at: string
          created_by: string | null
          document_version_id: string
          id: string
          org_id: string
          source_analysis_run_id: string
        }
        Insert: {
          binding_reason: string
          created_at?: string
          created_by?: string | null
          document_version_id: string
          id?: string
          org_id: string
          source_analysis_run_id: string
        }
        Update: {
          binding_reason?: string
          created_at?: string
          created_by?: string | null
          document_version_id?: string
          id?: string
          org_id?: string
          source_analysis_run_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_version_analysis_bindings_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_version_analysis_bindings_run_org_fkey"
            columns: ["org_id", "source_analysis_run_id"]
            isOneToOne: false
            referencedRelation: "source_analysis_runs"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "document_version_analysis_bindings_version_org_fkey"
            columns: ["org_id", "document_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      document_versions: {
        Row: {
          asset_id: string
          created_at: string
          created_by: string | null
          document_id: string
          failed_at: string | null
          id: string
          org_id: string
          original_filename: string
          page_count: number | null
          promoted_at: string | null
          replacement_reason: string | null
          state: Database["public"]["Enums"]["document_version_state"]
          superseded_at: string | null
          validated_at: string | null
          validation_state: Database["public"]["Enums"]["document_version_validation_state"]
          version_number: number
        }
        Insert: {
          asset_id: string
          created_at?: string
          created_by?: string | null
          document_id: string
          failed_at?: string | null
          id?: string
          org_id: string
          original_filename: string
          page_count?: number | null
          promoted_at?: string | null
          replacement_reason?: string | null
          state?: Database["public"]["Enums"]["document_version_state"]
          superseded_at?: string | null
          validated_at?: string | null
          validation_state?: Database["public"]["Enums"]["document_version_validation_state"]
          version_number: number
        }
        Update: {
          asset_id?: string
          created_at?: string
          created_by?: string | null
          document_id?: string
          failed_at?: string | null
          id?: string
          org_id?: string
          original_filename?: string
          page_count?: number | null
          promoted_at?: string | null
          replacement_reason?: string | null
          state?: Database["public"]["Enums"]["document_version_state"]
          superseded_at?: string | null
          validated_at?: string | null
          validation_state?: Database["public"]["Enums"]["document_version_validation_state"]
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "document_versions_asset_org_fkey"
            columns: ["org_id", "asset_id"]
            isOneToOne: false
            referencedRelation: "file_assets"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "document_versions_document_org_fkey"
            columns: ["org_id", "document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "document_versions_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      documents: {
        Row: {
          ai_prompt_version: string | null
          confidence_scores: Json | null
          content_availability: Database["public"]["Enums"]["document_content_availability"]
          content_hash: string | null
          copied_from_document_id: string | null
          created_at: string
          created_by: string | null
          current_version_id: string | null
          deleted_at: string | null
          direction: Database["public"]["Enums"]["doc_direction"] | null
          display_title: string | null
          doc_date: string | null
          doc_type: string | null
          document_category: string | null
          document_class: string | null
          effective_filename: string | null
          effective_size_bytes: number | null
          embedding: string | null
          embedding_model: string | null
          embedding_version: string | null
          file_hash_sha256: string | null
          financial_year: string | null
          id: string
          issued_by: string | null
          lifecycle_revision: number
          lifecycle_updated_at: string
          matter_id: string
          org_id: string
          origin_external_key: string | null
          origin_kind: Database["public"]["Enums"]["document_origin_kind"]
          raw_metadata: Json | null
          record_state: Database["public"]["Enums"]["document_record_state"]
          reference_number: string | null
          restored_at: string | null
          review_reason: string | null
          review_status: Database["public"]["Enums"]["doc_review_status"]
          reviewed_at: string | null
          reviewed_by: string | null
          search_vector: unknown
          source: string | null
          status: Database["public"]["Enums"]["doc_status"]
          storage_path: string | null
          summary: string | null
          trashed_at: string | null
          trashed_by: string | null
          trashed_reason: string | null
        }
        Insert: {
          ai_prompt_version?: string | null
          confidence_scores?: Json | null
          content_availability?: Database["public"]["Enums"]["document_content_availability"]
          content_hash?: string | null
          copied_from_document_id?: string | null
          created_at?: string
          created_by?: string | null
          current_version_id?: string | null
          deleted_at?: string | null
          direction?: Database["public"]["Enums"]["doc_direction"] | null
          display_title?: string | null
          doc_date?: string | null
          doc_type?: string | null
          document_category?: string | null
          document_class?: string | null
          effective_filename?: string | null
          effective_size_bytes?: number | null
          embedding?: string | null
          embedding_model?: string | null
          embedding_version?: string | null
          file_hash_sha256?: string | null
          financial_year?: string | null
          id?: string
          issued_by?: string | null
          lifecycle_revision?: number
          lifecycle_updated_at?: string
          matter_id: string
          org_id: string
          origin_external_key?: string | null
          origin_kind?: Database["public"]["Enums"]["document_origin_kind"]
          raw_metadata?: Json | null
          record_state?: Database["public"]["Enums"]["document_record_state"]
          reference_number?: string | null
          restored_at?: string | null
          review_reason?: string | null
          review_status?: Database["public"]["Enums"]["doc_review_status"]
          reviewed_at?: string | null
          reviewed_by?: string | null
          search_vector?: unknown
          source?: string | null
          status?: Database["public"]["Enums"]["doc_status"]
          storage_path?: string | null
          summary?: string | null
          trashed_at?: string | null
          trashed_by?: string | null
          trashed_reason?: string | null
        }
        Update: {
          ai_prompt_version?: string | null
          confidence_scores?: Json | null
          content_availability?: Database["public"]["Enums"]["document_content_availability"]
          content_hash?: string | null
          copied_from_document_id?: string | null
          created_at?: string
          created_by?: string | null
          current_version_id?: string | null
          deleted_at?: string | null
          direction?: Database["public"]["Enums"]["doc_direction"] | null
          display_title?: string | null
          doc_date?: string | null
          doc_type?: string | null
          document_category?: string | null
          document_class?: string | null
          effective_filename?: string | null
          effective_size_bytes?: number | null
          embedding?: string | null
          embedding_model?: string | null
          embedding_version?: string | null
          file_hash_sha256?: string | null
          financial_year?: string | null
          id?: string
          issued_by?: string | null
          lifecycle_revision?: number
          lifecycle_updated_at?: string
          matter_id?: string
          org_id?: string
          origin_external_key?: string | null
          origin_kind?: Database["public"]["Enums"]["document_origin_kind"]
          raw_metadata?: Json | null
          record_state?: Database["public"]["Enums"]["document_record_state"]
          reference_number?: string | null
          restored_at?: string | null
          review_reason?: string | null
          review_status?: Database["public"]["Enums"]["doc_review_status"]
          reviewed_at?: string | null
          reviewed_by?: string | null
          search_vector?: unknown
          source?: string | null
          status?: Database["public"]["Enums"]["doc_status"]
          storage_path?: string | null
          summary?: string | null
          trashed_at?: string | null
          trashed_by?: string | null
          trashed_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "documents_copied_from_org_fkey"
            columns: ["org_id", "copied_from_document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "documents_current_version_org_fkey"
            columns: ["org_id", "current_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "documents_matter_id_fkey"
            columns: ["matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documents_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      file_assets: {
        Row: {
          availability: Database["public"]["Enums"]["file_asset_availability"]
          bucket_id: string
          byte_size: number | null
          created_at: string
          created_by: string | null
          detected_mime_type: string | null
          expired_at: string | null
          failed_at: string | null
          failure_code: string | null
          id: string
          object_key: string
          org_id: string
          sha256: string | null
          validated_at: string | null
          validated_page_count: number | null
        }
        Insert: {
          availability?: Database["public"]["Enums"]["file_asset_availability"]
          bucket_id: string
          byte_size?: number | null
          created_at?: string
          created_by?: string | null
          detected_mime_type?: string | null
          expired_at?: string | null
          failed_at?: string | null
          failure_code?: string | null
          id?: string
          object_key: string
          org_id: string
          sha256?: string | null
          validated_at?: string | null
          validated_page_count?: number | null
        }
        Update: {
          availability?: Database["public"]["Enums"]["file_asset_availability"]
          bucket_id?: string
          byte_size?: number | null
          created_at?: string
          created_by?: string | null
          detected_mime_type?: string | null
          expired_at?: string | null
          failed_at?: string | null
          failure_code?: string | null
          id?: string
          object_key?: string
          org_id?: string
          sha256?: string | null
          validated_at?: string | null
          validated_page_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "file_assets_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      intake_item_assignments: {
        Row: {
          assigned_by: string | null
          created_at: string
          document_id: string
          document_version_id: string | null
          id: string
          intake_item_id: string
          org_id: string
        }
        Insert: {
          assigned_by?: string | null
          created_at?: string
          document_id: string
          document_version_id?: string | null
          id?: string
          intake_item_id: string
          org_id: string
        }
        Update: {
          assigned_by?: string | null
          created_at?: string
          document_id?: string
          document_version_id?: string | null
          id?: string
          intake_item_id?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "intake_item_assignments_document_org_fkey"
            columns: ["org_id", "document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "intake_item_assignments_intake_org_fkey"
            columns: ["org_id", "intake_item_id"]
            isOneToOne: false
            referencedRelation: "intake_items"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "intake_item_assignments_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "intake_item_assignments_version_org_fkey"
            columns: ["org_id", "document_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      intake_items: {
        Row: {
          asset_id: string
          assigned_at: string | null
          created_at: string
          discarded_at: string | null
          expired_at: string | null
          failed_at: string | null
          failure_code: string | null
          id: string
          intended_matter_id: string | null
          org_id: string
          state: Database["public"]["Enums"]["intake_item_state"]
          updated_at: string
          upload_session_id: string | null
          uploaded_by: string | null
        }
        Insert: {
          asset_id: string
          assigned_at?: string | null
          created_at?: string
          discarded_at?: string | null
          expired_at?: string | null
          failed_at?: string | null
          failure_code?: string | null
          id?: string
          intended_matter_id?: string | null
          org_id: string
          state?: Database["public"]["Enums"]["intake_item_state"]
          updated_at?: string
          upload_session_id?: string | null
          uploaded_by?: string | null
        }
        Update: {
          asset_id?: string
          assigned_at?: string | null
          created_at?: string
          discarded_at?: string | null
          expired_at?: string | null
          failed_at?: string | null
          failure_code?: string | null
          id?: string
          intended_matter_id?: string | null
          org_id?: string
          state?: Database["public"]["Enums"]["intake_item_state"]
          updated_at?: string
          upload_session_id?: string | null
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "intake_items_asset_org_fkey"
            columns: ["org_id", "asset_id"]
            isOneToOne: false
            referencedRelation: "file_assets"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "intake_items_matter_org_fkey"
            columns: ["org_id", "intended_matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "intake_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "intake_items_session_org_fkey"
            columns: ["org_id", "upload_session_id"]
            isOneToOne: false
            referencedRelation: "upload_sessions"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      matters: {
        Row: {
          client_id: string
          created_at: string
          deleted_at: string | null
          description: string | null
          financial_year: string
          id: string
          matter_code: string | null
          org_id: string
          status: Database["public"]["Enums"]["matter_status"]
          title: string
        }
        Insert: {
          client_id: string
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          financial_year?: string
          id?: string
          matter_code?: string | null
          org_id: string
          status?: Database["public"]["Enums"]["matter_status"]
          title: string
        }
        Update: {
          client_id?: string
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          financial_year?: string
          id?: string
          matter_code?: string | null
          org_id?: string
          status?: Database["public"]["Enums"]["matter_status"]
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "matters_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "matters_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      model_pricing: {
        Row: {
          created_at: string
          input_price_per_1m: number
          model_name: string
          output_price_per_1m: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          input_price_per_1m: number
          model_name: string
          output_price_per_1m: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          input_price_per_1m?: number
          model_name?: string
          output_price_per_1m?: number
          updated_at?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          entity_id: string | null
          entity_type: Database["public"]["Enums"]["entity_type"] | null
          id: string
          is_read: boolean
          org_id: string
          title: string
          type: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          id?: string
          is_read?: boolean
          org_id: string
          title: string
          type: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          id?: string
          is_read?: boolean
          org_id?: string
          title?: string
          type?: Database["public"]["Enums"]["notification_type"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      org_invites: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          invited_by: string
          invited_email: string
          org_id: string
          role: Database["public"]["Enums"]["org_member_role"]
          status: Database["public"]["Enums"]["invite_status"]
          token: string | null
        }
        Insert: {
          created_at?: string
          expires_at?: string
          id?: string
          invited_by: string
          invited_email: string
          org_id: string
          role?: Database["public"]["Enums"]["org_member_role"]
          status?: Database["public"]["Enums"]["invite_status"]
          token?: string | null
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          invited_by?: string
          invited_email?: string
          org_id?: string
          role?: Database["public"]["Enums"]["org_member_role"]
          status?: Database["public"]["Enums"]["invite_status"]
          token?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "org_invites_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      org_members: {
        Row: {
          joined_at: string
          org_id: string
          role: Database["public"]["Enums"]["org_member_role"]
          user_id: string
        }
        Insert: {
          joined_at?: string
          org_id: string
          role?: Database["public"]["Enums"]["org_member_role"]
          user_id: string
        }
        Update: {
          joined_at?: string
          org_id?: string
          role?: Database["public"]["Enums"]["org_member_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_members_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      organisation_invitation_accept_intents: {
        Row: {
          consumed_at: string | null
          created_at: string
          expires_at: string
          id: string
          invite_id: string
          nonce_hash: string
        }
        Insert: {
          consumed_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          invite_id: string
          nonce_hash: string
        }
        Update: {
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          invite_id?: string
          nonce_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisation_invitation_accept_intents_invite_id_fkey"
            columns: ["invite_id"]
            isOneToOne: false
            referencedRelation: "organisation_invites"
            referencedColumns: ["id"]
          },
        ]
      }
      organisation_invitation_command_receipts: {
        Row: {
          actor_user_id: string
          command_kind: string
          created_at: string
          idempotency_key: string
          invite_id: string | null
          result_code: string
          result_org_id: string | null
        }
        Insert: {
          actor_user_id: string
          command_kind: string
          created_at?: string
          idempotency_key: string
          invite_id?: string | null
          result_code: string
          result_org_id?: string | null
        }
        Update: {
          actor_user_id?: string
          command_kind?: string
          created_at?: string
          idempotency_key?: string
          invite_id?: string | null
          result_code?: string
          result_org_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organisation_invitation_command_receipts_invite_id_fkey"
            columns: ["invite_id"]
            isOneToOne: false
            referencedRelation: "organisation_invites"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organisation_invitation_command_receipts_result_org_id_fkey"
            columns: ["result_org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      organisation_invite_deliveries: {
        Row: {
          created_at: string
          created_by: string | null
          error_code: string | null
          failed_at: string | null
          id: string
          idempotency_key: string
          invite_id: string
          provider_reference: string | null
          scheduled_at: string
          sent_at: string | null
          state: string
          token_version: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          error_code?: string | null
          failed_at?: string | null
          id?: string
          idempotency_key?: string
          invite_id: string
          provider_reference?: string | null
          scheduled_at?: string
          sent_at?: string | null
          state?: string
          token_version: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          error_code?: string | null
          failed_at?: string | null
          id?: string
          idempotency_key?: string
          invite_id?: string
          provider_reference?: string | null
          scheduled_at?: string
          sent_at?: string | null
          state?: string
          token_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisation_invite_deliveries_invite_id_fkey"
            columns: ["invite_id"]
            isOneToOne: false
            referencedRelation: "organisation_invites"
            referencedColumns: ["id"]
          },
        ]
      }
      organisation_invites: {
        Row: {
          accepted_at: string | null
          accepted_by_user_id: string | null
          accepted_membership_id: string | null
          correlation_id: string
          created_at: string
          expired_at: string | null
          expires_at: string
          id: string
          idempotency_key: string
          invited_by_membership_id: string | null
          invited_by_user_id: string | null
          lifecycle_actor_id: string | null
          lifecycle_reason: string | null
          normalized_email: string
          org_id: string
          rejected_at: string | null
          revision: number
          revoked_at: string | null
          role: Database["public"]["Enums"]["org_member_role"]
          selector_hash: string | null
          state: Database["public"]["Enums"]["organisation_invite_state"]
          superseded_at: string | null
          superseded_by_id: string | null
          token_version: number
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          accepted_membership_id?: string | null
          correlation_id?: string
          created_at?: string
          expired_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key?: string
          invited_by_membership_id?: string | null
          invited_by_user_id?: string | null
          lifecycle_actor_id?: string | null
          lifecycle_reason?: string | null
          normalized_email: string
          org_id: string
          rejected_at?: string | null
          revision?: number
          revoked_at?: string | null
          role: Database["public"]["Enums"]["org_member_role"]
          selector_hash?: string | null
          state?: Database["public"]["Enums"]["organisation_invite_state"]
          superseded_at?: string | null
          superseded_by_id?: string | null
          token_version?: number
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          accepted_membership_id?: string | null
          correlation_id?: string
          created_at?: string
          expired_at?: string | null
          expires_at?: string
          id?: string
          idempotency_key?: string
          invited_by_membership_id?: string | null
          invited_by_user_id?: string | null
          lifecycle_actor_id?: string | null
          lifecycle_reason?: string | null
          normalized_email?: string
          org_id?: string
          rejected_at?: string | null
          revision?: number
          revoked_at?: string | null
          role?: Database["public"]["Enums"]["org_member_role"]
          selector_hash?: string | null
          state?: Database["public"]["Enums"]["organisation_invite_state"]
          superseded_at?: string | null
          superseded_by_id?: string | null
          token_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisation_invites_accepted_membership_id_fkey"
            columns: ["accepted_membership_id"]
            isOneToOne: false
            referencedRelation: "organisation_memberships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organisation_invites_invited_by_membership_id_fkey"
            columns: ["invited_by_membership_id"]
            isOneToOne: false
            referencedRelation: "organisation_memberships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organisation_invites_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organisation_invites_superseded_by_id_fkey"
            columns: ["superseded_by_id"]
            isOneToOne: false
            referencedRelation: "organisation_invites"
            referencedColumns: ["id"]
          },
        ]
      }
      organisation_memberships: {
        Row: {
          created_at: string
          generation: number
          id: string
          invited_through_id: string | null
          joined_at: string
          joined_by: string | null
          org_id: string
          removal_reason: string | null
          removed_at: string | null
          removed_by: string | null
          revision: number
          role: Database["public"]["Enums"]["org_member_role"]
          state: Database["public"]["Enums"]["organisation_membership_state"]
          suspended_at: string | null
          suspended_by: string | null
          suspension_reason: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          generation: number
          id?: string
          invited_through_id?: string | null
          joined_at?: string
          joined_by?: string | null
          org_id: string
          removal_reason?: string | null
          removed_at?: string | null
          removed_by?: string | null
          revision?: number
          role?: Database["public"]["Enums"]["org_member_role"]
          state?: Database["public"]["Enums"]["organisation_membership_state"]
          suspended_at?: string | null
          suspended_by?: string | null
          suspension_reason?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          generation?: number
          id?: string
          invited_through_id?: string | null
          joined_at?: string
          joined_by?: string | null
          org_id?: string
          removal_reason?: string | null
          removed_at?: string | null
          removed_by?: string | null
          revision?: number
          role?: Database["public"]["Enums"]["org_member_role"]
          state?: Database["public"]["Enums"]["organisation_membership_state"]
          suspended_at?: string | null
          suspended_by?: string | null
          suspension_reason?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisation_memberships_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      organisation_storage_policies: {
        Row: {
          created_at: string
          max_pdf_bytes: number
          org_id: string
          unique_asset_entitlement_bytes: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          max_pdf_bytes?: number
          org_id: string
          unique_asset_entitlement_bytes?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          max_pdf_bytes?: number
          org_id?: string
          unique_asset_entitlement_bytes?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisation_storage_policies_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: true
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      organisations: {
        Row: {
          created_at: string
          created_by: string
          id: string
          name: string
          owner_membership_id: string | null
          revision: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          name: string
          owner_membership_id?: string | null
          revision?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          name?: string
          owner_membership_id?: string | null
          revision?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisations_owner_membership_id_fkey"
            columns: ["owner_membership_id"]
            isOneToOne: false
            referencedRelation: "organisation_memberships"
            referencedColumns: ["id"]
          },
        ]
      }
      outbox_dispatch_attempts: {
        Row: {
          attempt_number: number
          created_at: string
          event_id: string
          id: string
          lease_fingerprint: string
          org_id: string
          outcome: string
          safe_error_code: string | null
          trigger_run_id: string | null
        }
        Insert: {
          attempt_number: number
          created_at?: string
          event_id: string
          id?: string
          lease_fingerprint: string
          org_id: string
          outcome: string
          safe_error_code?: string | null
          trigger_run_id?: string | null
        }
        Update: {
          attempt_number?: number
          created_at?: string
          event_id?: string
          id?: string
          lease_fingerprint?: string
          org_id?: string
          outcome?: string
          safe_error_code?: string | null
          trigger_run_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "outbox_dispatch_attempts_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "outbox_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "outbox_dispatch_attempts_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      outbox_events: {
        Row: {
          aggregate_id: string
          aggregate_type: string
          attempt_count: number
          created_at: string
          delivered_at: string | null
          delivery_state: Database["public"]["Enums"]["outbox_delivery_state"]
          event_kind: string
          failed_at: string | null
          id: string
          idempotency_key: string
          last_attempt_at: string | null
          last_error_code: string | null
          lease_expires_at: string | null
          lease_token: string | null
          next_attempt_at: string
          org_id: string
          payload: Json
          trigger_run_id: string | null
          updated_at: string
        }
        Insert: {
          aggregate_id: string
          aggregate_type: string
          attempt_count?: number
          created_at?: string
          delivered_at?: string | null
          delivery_state?: Database["public"]["Enums"]["outbox_delivery_state"]
          event_kind: string
          failed_at?: string | null
          id?: string
          idempotency_key: string
          last_attempt_at?: string | null
          last_error_code?: string | null
          lease_expires_at?: string | null
          lease_token?: string | null
          next_attempt_at?: string
          org_id: string
          payload?: Json
          trigger_run_id?: string | null
          updated_at?: string
        }
        Update: {
          aggregate_id?: string
          aggregate_type?: string
          attempt_count?: number
          created_at?: string
          delivered_at?: string | null
          delivery_state?: Database["public"]["Enums"]["outbox_delivery_state"]
          event_kind?: string
          failed_at?: string | null
          id?: string
          idempotency_key?: string
          last_attempt_at?: string | null
          last_error_code?: string | null
          lease_expires_at?: string | null
          lease_token?: string | null
          next_attempt_at?: string
          org_id?: string
          payload?: Json
          trigger_run_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "outbox_events_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_storage_policy: {
        Row: {
          created_at: string
          singleton: boolean
          unique_asset_guard_bytes: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          singleton?: boolean
          unique_asset_guard_bytes?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          singleton?: boolean
          unique_asset_guard_bytes?: number
          updated_at?: string
        }
        Relationships: []
      }
      source_analysis_runs: {
        Row: {
          asset_id: string
          attempt_count: number
          completed_at: string | null
          created_at: string
          failed_at: string | null
          heartbeat_at: string | null
          id: string
          lease_expires_at: string | null
          lease_token: string | null
          org_id: string
          outbox_event_id: string | null
          page_content_version: number
          request_key: string
          safe_error_code: string | null
          started_at: string | null
          state: Database["public"]["Enums"]["source_analysis_run_state"]
        }
        Insert: {
          asset_id: string
          attempt_count?: number
          completed_at?: string | null
          created_at?: string
          failed_at?: string | null
          heartbeat_at?: string | null
          id?: string
          lease_expires_at?: string | null
          lease_token?: string | null
          org_id: string
          outbox_event_id?: string | null
          page_content_version?: number
          request_key: string
          safe_error_code?: string | null
          started_at?: string | null
          state?: Database["public"]["Enums"]["source_analysis_run_state"]
        }
        Update: {
          asset_id?: string
          attempt_count?: number
          completed_at?: string | null
          created_at?: string
          failed_at?: string | null
          heartbeat_at?: string | null
          id?: string
          lease_expires_at?: string | null
          lease_token?: string | null
          org_id?: string
          outbox_event_id?: string | null
          page_content_version?: number
          request_key?: string
          safe_error_code?: string | null
          started_at?: string | null
          state?: Database["public"]["Enums"]["source_analysis_run_state"]
        }
        Relationships: [
          {
            foreignKeyName: "source_analysis_runs_asset_org_fkey"
            columns: ["org_id", "asset_id"]
            isOneToOne: false
            referencedRelation: "file_assets"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "source_analysis_runs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "source_analysis_runs_outbox_event_id_fkey"
            columns: ["outbox_event_id"]
            isOneToOne: true
            referencedRelation: "outbox_events"
            referencedColumns: ["id"]
          },
        ]
      }
      staged_documents: {
        Row: {
          confidence_scores: Json | null
          created_at: string
          document_text: string | null
          extracted_fy: string | null
          extracted_gstin: string | null
          id: string
          intake_matter_id: string | null
          org_id: string
          raw_metadata: Json | null
          status: Database["public"]["Enums"]["staged_status"]
          storage_path: string
          suggested_client_id: string | null
          suggested_matter_id: string | null
          suggested_matter_ids: Json | null
          suggestion_reason: string | null
          uploaded_by: string
        }
        Insert: {
          confidence_scores?: Json | null
          created_at?: string
          document_text?: string | null
          extracted_fy?: string | null
          extracted_gstin?: string | null
          id?: string
          intake_matter_id?: string | null
          org_id: string
          raw_metadata?: Json | null
          status?: Database["public"]["Enums"]["staged_status"]
          storage_path: string
          suggested_client_id?: string | null
          suggested_matter_id?: string | null
          suggested_matter_ids?: Json | null
          suggestion_reason?: string | null
          uploaded_by: string
        }
        Update: {
          confidence_scores?: Json | null
          created_at?: string
          document_text?: string | null
          extracted_fy?: string | null
          extracted_gstin?: string | null
          id?: string
          intake_matter_id?: string | null
          org_id?: string
          raw_metadata?: Json | null
          status?: Database["public"]["Enums"]["staged_status"]
          storage_path?: string
          suggested_client_id?: string | null
          suggested_matter_id?: string | null
          suggested_matter_ids?: Json | null
          suggestion_reason?: string | null
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "staged_documents_intake_matter_id_fkey"
            columns: ["intake_matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staged_documents_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staged_documents_suggested_client_id_fkey"
            columns: ["suggested_client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staged_documents_suggested_matter_id_fkey"
            columns: ["suggested_matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["id"]
          },
        ]
      }
      storage_reservations: {
        Row: {
          consumed_at: string | null
          created_at: string
          expired_at: string | null
          expires_at: string
          id: string
          org_id: string
          released_at: string | null
          reserved_bytes: number
          state: Database["public"]["Enums"]["storage_reservation_state"]
          upload_session_id: string
        }
        Insert: {
          consumed_at?: string | null
          created_at?: string
          expired_at?: string | null
          expires_at?: string
          id?: string
          org_id: string
          released_at?: string | null
          reserved_bytes: number
          state?: Database["public"]["Enums"]["storage_reservation_state"]
          upload_session_id: string
        }
        Update: {
          consumed_at?: string | null
          created_at?: string
          expired_at?: string | null
          expires_at?: string
          id?: string
          org_id?: string
          released_at?: string | null
          reserved_bytes?: number
          state?: Database["public"]["Enums"]["storage_reservation_state"]
          upload_session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "storage_reservations_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "storage_reservations_session_org_fkey"
            columns: ["org_id", "upload_session_id"]
            isOneToOne: false
            referencedRelation: "upload_sessions"
            referencedColumns: ["org_id", "id"]
          },
        ]
      }
      supporting_doc_links: {
        Row: {
          created_at: string
          created_by: string | null
          document_id: string
          id: string
          note: string | null
          supporting_doc_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          document_id: string
          id?: string
          note?: string | null
          supporting_doc_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          document_id?: string
          id?: string
          note?: string | null
          supporting_doc_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "supporting_doc_links_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supporting_doc_links_supporting_doc_id_fkey"
            columns: ["supporting_doc_id"]
            isOneToOne: false
            referencedRelation: "supporting_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      supporting_documents: {
        Row: {
          amount: number | null
          category: Database["public"]["Enums"]["supporting_doc_category"]
          created_at: string
          created_by: string | null
          deleted_at: string | null
          description: string | null
          doc_date: string | null
          id: string
          matter_id: string
          org_id: string
          parties: string[] | null
          raw_metadata: Json | null
          storage_path: string
          title: string
          was_promoted: boolean
        }
        Insert: {
          amount?: number | null
          category?: Database["public"]["Enums"]["supporting_doc_category"]
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          doc_date?: string | null
          id?: string
          matter_id: string
          org_id: string
          parties?: string[] | null
          raw_metadata?: Json | null
          storage_path: string
          title: string
          was_promoted?: boolean
        }
        Update: {
          amount?: number | null
          category?: Database["public"]["Enums"]["supporting_doc_category"]
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          doc_date?: string | null
          id?: string
          matter_id?: string
          org_id?: string
          parties?: string[] | null
          raw_metadata?: Json | null
          storage_path?: string
          title?: string
          was_promoted?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "supporting_documents_matter_id_fkey"
            columns: ["matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supporting_documents_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      upload_sessions: {
        Row: {
          asset_id: string
          created_at: string
          created_by: string | null
          declared_byte_size: number
          declared_filename: string
          declared_mime_type: string | null
          expired_at: string | null
          expires_at: string
          failed_at: string | null
          failure_code: string | null
          finalized_at: string | null
          id: string
          idempotency_key: string | null
          org_id: string
          state: Database["public"]["Enums"]["upload_session_state"]
          uploaded_at: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string
          created_by?: string | null
          declared_byte_size: number
          declared_filename: string
          declared_mime_type?: string | null
          expired_at?: string | null
          expires_at?: string
          failed_at?: string | null
          failure_code?: string | null
          finalized_at?: string | null
          id?: string
          idempotency_key?: string | null
          org_id: string
          state?: Database["public"]["Enums"]["upload_session_state"]
          uploaded_at?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string
          created_by?: string | null
          declared_byte_size?: number
          declared_filename?: string
          declared_mime_type?: string | null
          expired_at?: string | null
          expires_at?: string
          failed_at?: string | null
          failure_code?: string | null
          finalized_at?: string | null
          id?: string
          idempotency_key?: string | null
          org_id?: string
          state?: Database["public"]["Enums"]["upload_session_state"]
          uploaded_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "upload_sessions_asset_org_fkey"
            columns: ["org_id", "asset_id"]
            isOneToOne: false
            referencedRelation: "file_assets"
            referencedColumns: ["org_id", "id"]
          },
          {
            foreignKeyName: "upload_sessions_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      user_notification_prefs: {
        Row: {
          email_on_deadline: boolean
          email_on_failure: boolean
          email_on_invite: boolean
          email_on_mention: boolean
          email_on_new_doc: boolean
          org_id: string
          user_id: string
        }
        Insert: {
          email_on_deadline?: boolean
          email_on_failure?: boolean
          email_on_invite?: boolean
          email_on_mention?: boolean
          email_on_new_doc?: boolean
          org_id: string
          user_id: string
        }
        Update: {
          email_on_deadline?: boolean
          email_on_failure?: boolean
          email_on_invite?: boolean
          email_on_mention?: boolean
          email_on_new_doc?: boolean
          org_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_notification_prefs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      user_profiles: {
        Row: {
          created_at: string
          display_name: string | null
          locale: string
          professional_title: string | null
          revision: number
          timezone: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          locale?: string
          professional_title?: string | null
          revision?: number
          timezone?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          locale?: string
          professional_title?: string | null
          revision?: number
          timezone?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      wiki_section_versions: {
        Row: {
          content: Json
          created_at: string
          generated_by: string
          id: string
          wiki_section_id: string
        }
        Insert: {
          content: Json
          created_at?: string
          generated_by: string
          id?: string
          wiki_section_id: string
        }
        Update: {
          content?: Json
          created_at?: string
          generated_by?: string
          id?: string
          wiki_section_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wiki_section_versions_wiki_section_id_fkey"
            columns: ["wiki_section_id"]
            isOneToOne: false
            referencedRelation: "wiki_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      wiki_sections: {
        Row: {
          content: Json | null
          id: string
          is_user_edited: boolean
          last_ai_content: Json | null
          matter_id: string
          section_key: string
          title: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          content?: Json | null
          id?: string
          is_user_edited?: boolean
          last_ai_content?: Json | null
          matter_id: string
          section_key: string
          title: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          content?: Json | null
          id?: string
          is_user_edited?: boolean
          last_ai_content?: Json | null
          matter_id?: string
          section_key?: string
          title?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wiki_sections_matter_id_fkey"
            columns: ["matter_id"]
            isOneToOne: false
            referencedRelation: "matters"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      document_lifecycle_foundation_diagnostics: {
        Row: {
          document_id: string | null
          issue: string | null
          org_id: string | null
        }
        Relationships: []
      }
      document_materialization_diagnostics: {
        Row: {
          document_id: string | null
          issue: string | null
          org_id: string | null
        }
        Relationships: []
      }
      document_outbox_dispatch_diagnostics: {
        Row: {
          delivery_state:
            | Database["public"]["Enums"]["outbox_delivery_state"]
            | null
          event_count: number | null
          oldest_due_at: string | null
          oldest_lease_age: string | null
        }
        Relationships: []
      }
      document_processing_orchestration_diagnostics: {
        Row: {
          oldest_age: string | null
          run_count: number | null
          run_kind: string | null
          safe_error_code: string | null
          state: string | null
        }
        Relationships: []
      }
      document_upload_command_diagnostics: {
        Row: {
          issue: string | null
          org_id: string | null
          upload_session_id: string | null
        }
        Relationships: []
      }
      organisation_identity_cutover_diagnostics: {
        Row: {
          detail: Json | null
          issue_code: string | null
          membership_id: string | null
          org_id: string | null
          user_id: string | null
        }
        Relationships: []
      }
      organisation_invitation_cutover_diagnostics: {
        Row: {
          id: string | null
          issue_code: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      accept_organisation_invite: {
        Args: {
          p_idempotency_key?: string
          p_invite_id?: string
          p_nonce_hash?: string
          p_selector_hash?: string
        }
        Returns: {
          code: string
          org_id: string
        }[]
      }
      ack_document_outbox_event: {
        Args: {
          p_event_id: string
          p_lease_token: string
          p_trigger_run_id: string
        }
        Returns: {
          code: string
        }[]
      }
      assign_intake_to_new_document: {
        Args: {
          p_display_title: string
          p_expected_intake_uploader: string
          p_idempotency: string
          p_intake_id: string
          p_matter_id: string
        }
        Returns: {
          code: string
          document_id: string
          document_version_id: string
          lifecycle_revision: number
        }[]
      }
      attach_intake_to_document: {
        Args: {
          p_document_id: string
          p_expected_intake_uploader: string
          p_expected_revision: number
          p_idempotency: string
          p_intake_id: string
        }
        Returns: {
          code: string
          document_version_id: string
          lifecycle_revision: number
        }[]
      }
      begin_organisation_invitation_accept_intent: {
        Args: { p_nonce_hash: string; p_selector_hash: string }
        Returns: {
          code: string
        }[]
      }
      claim_document_processing_work: {
        Args: { p_event_id: string; p_trigger_run_id?: string }
        Returns: {
          actor_id: string
          bucket_id: string
          code: string
          document_id: string
          document_version_id: string
          lease_token: string
          matter_id: string
          object_key: string
          processing_run_id: string
        }[]
      }
      claim_document_validation_work: {
        Args: { p_event_id: string }
        Returns: {
          asset_id: string
          bucket_id: string
          code: string
          expected_bytes: number
          intake_id: string
          lease_token: string
          object_key: string
          source_run_id: string
        }[]
      }
      complete_document_upload: {
        Args: {
          p_detected_mime: string
          p_idempotency: string
          p_observed_bytes: number
          p_session: string
          p_sha256: string
        }
        Returns: {
          asset_id: string
          code: string
          duplicate_asset_id: string
          intake_item_id: string
          upload_session_id: string
        }[]
      }
      create_metadata_only_document: {
        Args: {
          p_display_title: string
          p_doc_date: string
          p_doc_type: string
          p_idempotency: string
          p_matter_id: string
          p_reference_number: string
        }
        Returns: {
          code: string
          document_id: string
          lifecycle_revision: number
        }[]
      }
      create_organisation_invite: {
        Args: {
          p_email: string
          p_idempotency_key: string
          p_role: Database["public"]["Enums"]["org_member_role"]
          p_selector_hash: string
        }
        Returns: {
          code: string
          invite_id: string
          inviter_name: string
          org_name: string
          retry_after: string
          token_version: number
        }[]
      }
      document_lifecycle_payload_is_safe: {
        Args: { payload: Json }
        Returns: boolean
      }
      document_materialization_actor: {
        Args: { p_capability: string }
        Returns: {
          actor_id: string
          org_id: string
        }[]
      }
      document_materialization_insert_version: {
        Args: {
          p_actor: string
          p_document: string
          p_intake: string
          p_org: string
          p_reason?: string
        }
        Returns: string
      }
      document_materialization_safe_event: {
        Args: {
          p_aggregate: string
          p_key: string
          p_kind: string
          p_org: string
          p_payload: Json
        }
        Returns: undefined
      }
      document_upload_safe_event: {
        Args: {
          p_aggregate: string
          p_key: string
          p_kind: string
          p_org: string
          p_payload: Json
        }
        Returns: undefined
      }
      fail_document_outbox_event: {
        Args: {
          p_event_id: string
          p_lease_token: string
          p_safe_error_code: string
        }
        Returns: {
          code: string
          next_attempt_at: string
        }[]
      }
      fail_document_upload: {
        Args: { p_error_code: string; p_idempotency: string; p_session: string }
        Returns: {
          asset_id: string
          code: string
          intake_item_id: string
          upload_session_id: string
        }[]
      }
      finish_document_processing_work: {
        Args: {
          p_lease_token: string
          p_outcome: string
          p_processing_run_id: string
        }
        Returns: {
          code: string
        }[]
      }
      finish_document_validation_work: {
        Args: {
          p_lease_token: string
          p_outcome: string
          p_page_count: number
          p_source_run_id: string
        }
        Returns: {
          code: string
        }[]
      }
      fuzzy_match_reference: {
        Args: { p_matter_id: string; p_reference_number: string }
        Returns: {
          doc_type: string
          id: string
          reference_number: string
          sim_score: number
        }[]
      }
      get_my_organisation_context: {
        Args: never
        Returns: {
          capabilities: string[]
          capability_version: number
          is_owner: boolean
          membership_id: string
          org_id: string
          revision: number
          role: Database["public"]["Enums"]["org_member_role"]
          state: Database["public"]["Enums"]["organisation_membership_state"]
        }[]
      }
      get_my_pending_organisation_invites: {
        Args: never
        Returns: {
          id: string
          org_name: string
          revision: number
          role: Database["public"]["Enums"]["org_member_role"]
        }[]
      }
      get_my_team_members: {
        Args: never
        Returns: {
          authorised_email: string
          capabilities: string[]
          display_name: string
          is_owner: boolean
          joined_at: string
          membership_id: string
          professional_title: string
          revision: number
          role: Database["public"]["Enums"]["org_member_role"]
          state: Database["public"]["Enums"]["organisation_membership_state"]
        }[]
      }
      get_organisation_invites: {
        Args: never
        Returns: {
          authorized_email: string
          created_at: string
          expires_at: string
          id: string
          revision: number
          role: Database["public"]["Enums"]["org_member_role"]
          state: Database["public"]["Enums"]["organisation_invite_state"]
        }[]
      }
      has_organisation_capability: {
        Args: { check_org_id: string; requested_capability: string }
        Returns: boolean
      }
      has_team_capability: {
        Args: { check_org_id: string; requested_capability: string }
        Returns: boolean
      }
      invitation_actor: {
        Args: { org: string }
        Returns: {
          is_owner: boolean
          membership_id: string
        }[]
      }
      invitation_event: {
        Args: {
          p_actor: string
          p_correlation: string
          p_idempotency: string
          p_kind: string
          p_org: string
          p_reason: string
          p_target: string
        }
        Returns: boolean
      }
      is_active_org_member: { Args: { check_org_id: string }; Returns: boolean }
      is_email_in_any_org: { Args: { search_email: string }; Returns: boolean }
      is_org_admin: { Args: { check_org_id: string }; Returns: boolean }
      is_org_member: { Args: { check_org_id: string }; Returns: boolean }
      lease_document_outbox_events: {
        Args: { p_lease_seconds?: number; p_limit?: number }
        Returns: {
          aggregate_id: string
          aggregate_type: string
          attempt_number: number
          event_id: string
          event_kind: string
          idempotency_key: string
          lease_token: string
          org_id: string
          payload: Json
        }[]
      }
      maintain_document_upload_sessions: {
        Args: { p_batch_size?: number }
        Returns: {
          expired_assets: number
          expired_intakes: number
          expired_reservations: number
          expired_sessions: number
        }[]
      }
      maintain_organisation_invitations: { Args: never; Returns: undefined }
      match_all_documents: {
        Args: {
          match_count: number
          match_threshold: number
          p_org_id: string
          query_embedding: string
        }
        Returns: {
          id: string
          reference_number: string
          similarity: number
        }[]
      }
      match_all_documents_v2: {
        Args: {
          match_count: number
          match_threshold: number
          p_embedding_model: string
          p_embedding_version: string
          p_org_id: string
          query_embedding: string
        }
        Returns: {
          id: string
          reference_number: string
          similarity: number
        }[]
      }
      match_documents: {
        Args: {
          match_count: number
          match_threshold: number
          p_matter_id: string
          query_embedding: string
        }
        Returns: {
          id: string
          reference_number: string
          similarity: number
        }[]
      }
      match_documents_v2: {
        Args: {
          match_count: number
          match_threshold: number
          p_embedding_model: string
          p_embedding_version: string
          p_matter_id: string
          query_embedding: string
        }
        Returns: {
          id: string
          reference_number: string
          similarity: number
        }[]
      }
      my_org_ids: { Args: never; Returns: string[] }
      org_wide_fuzzy_match_reference: {
        Args: { p_org_id: string; p_reference_number: string }
        Returns: {
          id: string
          matter_id: string
          reference_number: string
          sim_score: number
        }[]
      }
      record_organisation_invite_delivery: {
        Args: {
          p_error_code?: string
          p_invite_id: string
          p_provider_reference?: string
          p_state: string
        }
        Returns: {
          code: string
        }[]
      }
      replace_document_version: {
        Args: {
          p_document_id: string
          p_expected_intake_uploader: string
          p_expected_revision: number
          p_idempotency: string
          p_intake_id: string
          p_replacement_reason: string
        }
        Returns: {
          code: string
          document_version_id: string
          lifecycle_revision: number
        }[]
      }
      resend_organisation_invite: {
        Args: {
          p_expected_revision: number
          p_idempotency_key: string
          p_invite_id: string
          p_selector_hash: string
        }
        Returns: {
          code: string
          invite_id: string
          inviter_name: string
          org_name: string
          retry_after: string
          token_version: number
        }[]
      }
      reserve_document_upload: {
        Args: {
          p_declared_bytes: number
          p_filename: string
          p_idempotency: string
          p_intended_matter: string
          p_mime: string
        }
        Returns: {
          asset_id: string
          bucket_id: string
          code: string
          expires_at: string
          intake_item_id: string
          object_key: string
          retry_after: string
          upload_session_id: string
        }[]
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      transition_organisation_invite: {
        Args: {
          p_action: string
          p_expected_revision: number
          p_idempotency_key: string
          p_invite_id: string
          p_reason?: string
        }
        Returns: {
          code: string
        }[]
      }
      validate_document_intake_asset: {
        Args: {
          p_idempotency: string
          p_intake_id: string
          p_outcome: string
          p_page_count: number
        }
        Returns: {
          asset_id: string
          code: string
          intake_item_id: string
        }[]
      }
    }
    Enums: {
      deadline_type:
        | "appeal_window"
        | "pre_deposit"
        | "hearing_date"
        | "reply_deadline"
        | "stay_application"
        | "other"
      doc_direction: "incoming" | "outgoing"
      doc_review_status: "unreviewed" | "reviewed"
      doc_status:
        | "uploaded"
        | "processing"
        | "analyzed"
        | "placed"
        | "pending_placement"
        | "failed"
        | "needs_review"
      document_content_availability:
        | "metadata_only"
        | "source_attached"
        | "source_indexed"
        | "source_unreadable"
      document_origin_kind:
        | "upload"
        | "spreadsheet_import"
        | "manual_record"
        | "email_intake"
        | "api_intake"
        | "legacy_migration"
      document_processing_scope:
        | "validate"
        | "extract"
        | "ocr"
        | "relationships"
        | "search_index"
        | "full"
      document_processing_stage:
        | "queued"
        | "validating"
        | "extracting"
        | "matching"
        | "ready"
        | "review"
        | "failed"
      document_processing_state:
        | "queued"
        | "running"
        | "completed"
        | "failed"
        | "cancelled"
      document_record_state: "active" | "trashed"
      document_version_state: "pending" | "current" | "superseded" | "failed"
      document_version_validation_state: "pending" | "valid" | "invalid"
      entity_type:
        | "document"
        | "matter"
        | "client"
        | "case_note"
        | "document_link"
        | "deadline"
        | "wiki_section"
        | "organisation"
        | "user"
        | "staged_document"
        | "supporting_document"
      file_asset_availability:
        | "reserved"
        | "uploaded"
        | "validating"
        | "available"
        | "quarantined"
        | "failed"
        | "expired"
      intake_item_state:
        | "awaiting_upload"
        | "uploaded"
        | "validating"
        | "processing"
        | "ready"
        | "assigned"
        | "duplicate"
        | "failed"
        | "discarded"
        | "expired"
      invite_status: "pending" | "accepted" | "rejected" | "expired"
      link_status: "confirmed" | "pending" | "rejected"
      link_type:
        | "responds_to"
        | "arises_from"
        | "challenges"
        | "summarizes"
        | "supersedes"
        | "appeals_to"
        | "exhibit"
        | "attachment_to"
        | "references_doc"
      matter_status:
        | "active"
        | "stayed"
        | "disposed"
        | "appeal_pending"
        | "tribunal"
        | "high_court"
        | "supreme_court"
        | "closed"
      note_template_type:
        | "hearing_note"
        | "client_instruction"
        | "research_note"
        | "general"
      notification_type:
        | "org_invite"
        | "mention"
        | "deadline_approaching"
        | "document_ready"
        | "chain_suggestion"
        | "processing_failed"
        | "staged_doc_ready"
        | "wiki_ai_suggestion"
      org_member_role: "admin" | "associate" | "viewer"
      organisation_invite_state:
        | "pending"
        | "accepted"
        | "rejected"
        | "expired"
        | "revoked"
        | "superseded"
      organisation_membership_state: "active" | "suspended" | "removed"
      outbox_delivery_state:
        | "pending"
        | "leased"
        | "delivered"
        | "failed"
        | "dead_letter"
      source_analysis_run_state: "queued" | "running" | "succeeded" | "failed"
      staged_status:
        | "pending_assignment"
        | "analyzing"
        | "ready_to_assign"
        | "manually_assigned"
        | "failed"
        | "auto_assigned"
      storage_reservation_state: "active" | "consumed" | "released" | "expired"
      supporting_doc_category:
        | "invoices"
        | "bank_statements"
        | "contracts"
        | "correspondence"
        | "others"
      upload_session_state:
        | "reserved"
        | "uploading"
        | "uploaded"
        | "finalized"
        | "failed"
        | "expired"
        | "cancelled"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      deadline_type: [
        "appeal_window",
        "pre_deposit",
        "hearing_date",
        "reply_deadline",
        "stay_application",
        "other",
      ],
      doc_direction: ["incoming", "outgoing"],
      doc_review_status: ["unreviewed", "reviewed"],
      doc_status: [
        "uploaded",
        "processing",
        "analyzed",
        "placed",
        "pending_placement",
        "failed",
        "needs_review",
      ],
      document_content_availability: [
        "metadata_only",
        "source_attached",
        "source_indexed",
        "source_unreadable",
      ],
      document_origin_kind: [
        "upload",
        "spreadsheet_import",
        "manual_record",
        "email_intake",
        "api_intake",
        "legacy_migration",
      ],
      document_processing_scope: [
        "validate",
        "extract",
        "ocr",
        "relationships",
        "search_index",
        "full",
      ],
      document_processing_stage: [
        "queued",
        "validating",
        "extracting",
        "matching",
        "ready",
        "review",
        "failed",
      ],
      document_processing_state: [
        "queued",
        "running",
        "completed",
        "failed",
        "cancelled",
      ],
      document_record_state: ["active", "trashed"],
      document_version_state: ["pending", "current", "superseded", "failed"],
      document_version_validation_state: ["pending", "valid", "invalid"],
      entity_type: [
        "document",
        "matter",
        "client",
        "case_note",
        "document_link",
        "deadline",
        "wiki_section",
        "organisation",
        "user",
        "staged_document",
        "supporting_document",
      ],
      file_asset_availability: [
        "reserved",
        "uploaded",
        "validating",
        "available",
        "quarantined",
        "failed",
        "expired",
      ],
      intake_item_state: [
        "awaiting_upload",
        "uploaded",
        "validating",
        "processing",
        "ready",
        "assigned",
        "duplicate",
        "failed",
        "discarded",
        "expired",
      ],
      invite_status: ["pending", "accepted", "rejected", "expired"],
      link_status: ["confirmed", "pending", "rejected"],
      link_type: [
        "responds_to",
        "arises_from",
        "challenges",
        "summarizes",
        "supersedes",
        "appeals_to",
        "exhibit",
        "attachment_to",
        "references_doc",
      ],
      matter_status: [
        "active",
        "stayed",
        "disposed",
        "appeal_pending",
        "tribunal",
        "high_court",
        "supreme_court",
        "closed",
      ],
      note_template_type: [
        "hearing_note",
        "client_instruction",
        "research_note",
        "general",
      ],
      notification_type: [
        "org_invite",
        "mention",
        "deadline_approaching",
        "document_ready",
        "chain_suggestion",
        "processing_failed",
        "staged_doc_ready",
        "wiki_ai_suggestion",
      ],
      org_member_role: ["admin", "associate", "viewer"],
      organisation_invite_state: [
        "pending",
        "accepted",
        "rejected",
        "expired",
        "revoked",
        "superseded",
      ],
      organisation_membership_state: ["active", "suspended", "removed"],
      outbox_delivery_state: [
        "pending",
        "leased",
        "delivered",
        "failed",
        "dead_letter",
      ],
      source_analysis_run_state: ["queued", "running", "succeeded", "failed"],
      staged_status: [
        "pending_assignment",
        "analyzing",
        "ready_to_assign",
        "manually_assigned",
        "failed",
        "auto_assigned",
      ],
      storage_reservation_state: ["active", "consumed", "released", "expired"],
      supporting_doc_category: [
        "invoices",
        "bank_statements",
        "contracts",
        "correspondence",
        "others",
      ],
      upload_session_state: [
        "reserved",
        "uploading",
        "uploaded",
        "finalized",
        "failed",
        "expired",
        "cancelled",
      ],
    },
  },
} as const
