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
          parent_note_id: string | null
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
          parent_note_id?: string | null
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
          parent_note_id?: string | null
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
      documents: {
        Row: {
          ai_prompt_version: string | null
          confidence_scores: Json | null
          content_hash: string | null
          created_at: string
          created_by: string | null
          deleted_at: string | null
          direction: Database["public"]["Enums"]["doc_direction"] | null
          doc_date: string | null
          doc_type: string | null
          document_category: string | null
          document_class: string | null
          embedding: string | null
          file_hash_sha256: string | null
          financial_year: string | null
          id: string
          issued_by: string | null
          matter_id: string
          org_id: string
          raw_metadata: Json | null
          reference_number: string | null
          review_reason: string | null
          review_status: Database["public"]["Enums"]["doc_review_status"]
          reviewed_at: string | null
          reviewed_by: string | null
          search_vector: unknown
          source: string | null
          status: Database["public"]["Enums"]["doc_status"]
          storage_path: string
          summary: string | null
        }
        Insert: {
          ai_prompt_version?: string | null
          confidence_scores?: Json | null
          content_hash?: string | null
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          direction?: Database["public"]["Enums"]["doc_direction"] | null
          doc_date?: string | null
          doc_type?: string | null
          document_category?: string | null
          document_class?: string | null
          embedding?: string | null
          file_hash_sha256?: string | null
          financial_year?: string | null
          id?: string
          issued_by?: string | null
          matter_id: string
          org_id: string
          raw_metadata?: Json | null
          reference_number?: string | null
          review_reason?: string | null
          review_status?: Database["public"]["Enums"]["doc_review_status"]
          reviewed_at?: string | null
          reviewed_by?: string | null
          search_vector?: unknown
          source?: string | null
          status?: Database["public"]["Enums"]["doc_status"]
          storage_path: string
          summary?: string | null
        }
        Update: {
          ai_prompt_version?: string | null
          confidence_scores?: Json | null
          content_hash?: string | null
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          direction?: Database["public"]["Enums"]["doc_direction"] | null
          doc_date?: string | null
          doc_type?: string | null
          document_category?: string | null
          document_class?: string | null
          embedding?: string | null
          file_hash_sha256?: string | null
          financial_year?: string | null
          id?: string
          issued_by?: string | null
          matter_id?: string
          org_id?: string
          raw_metadata?: Json | null
          reference_number?: string | null
          review_reason?: string | null
          review_status?: Database["public"]["Enums"]["doc_review_status"]
          reviewed_at?: string | null
          reviewed_by?: string | null
          search_vector?: unknown
          source?: string | null
          status?: Database["public"]["Enums"]["doc_status"]
          storage_path?: string
          summary?: string | null
        }
        Relationships: [
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
          token: string
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
          token?: string
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
          token?: string
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
      organisations: {
        Row: {
          created_at: string
          created_by: string
          id: string
          name: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      staged_documents: {
        Row: {
          confidence_scores: Json | null
          created_at: string
          document_text: string | null
          extracted_fy: string | null
          extracted_gstin: string | null
          id: string
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
      [_ in never]: never
    }
    Functions: {
      fuzzy_match_reference: {
        Args: { p_matter_id: string; p_reference_number: string }
        Returns: {
          doc_type: string
          id: string
          reference_number: string
          sim_score: number
        }[]
      }
      is_org_admin: { Args: { check_org_id: string }; Returns: boolean }
      is_org_member: { Args: { check_org_id: string }; Returns: boolean }
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
      my_org_ids: { Args: never; Returns: string[] }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
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
      staged_status:
        | "pending_assignment"
        | "analyzing"
        | "ready_to_assign"
        | "assigned"
      supporting_doc_category:
        | "invoices"
        | "bank_statements"
        | "contracts"
        | "correspondence"
        | "others"
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
      staged_status: [
        "pending_assignment",
        "analyzing",
        "ready_to_assign",
        "assigned",
      ],
      supporting_doc_category: [
        "invoices",
        "bank_statements",
        "contracts",
        "correspondence",
        "others",
      ],
    },
  },
} as const

