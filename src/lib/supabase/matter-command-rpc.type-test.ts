import type { Database } from './database.types'

type CreateMatter = Database['public']['Functions']['create_matter_command']
type UpdateMatter = Database['public']['Functions']['update_matter_command']
type CreateResult = CreateMatter['Returns'][number]
type UpdateResult = UpdateMatter['Returns'][number]

const createArgs: CreateMatter['Args'] = {
  p_client_id: 'client', p_title: 'Matter', p_financial_year: '2024-25',
  p_description: '', p_status: 'active', p_idempotency_key: 'key',
}
const updateArgs: UpdateMatter['Args'] = {
  p_matter_id: 'matter', p_expected_revision: 1, p_title: 'Matter',
  p_financial_year: '2024-25', p_description: '', p_status: 'active',
  p_idempotency_key: 'key',
}
const nullableCreateMatterId: string | null = null as CreateResult['matter_id']
const nullableCreateClientId: string | null = null as CreateResult['client_id']
const nullableCreateRevision: number | null = null as CreateResult['revision']
const nullableUpdateMatterId: string | null = null as UpdateResult['matter_id']
const nullableUpdateClientId: string | null = null as UpdateResult['client_id']
const nullableUpdateRevision: number | null = null as UpdateResult['revision']

void createArgs
void updateArgs
void nullableCreateMatterId
void nullableCreateClientId
void nullableCreateRevision
void nullableUpdateMatterId
void nullableUpdateClientId
void nullableUpdateRevision
