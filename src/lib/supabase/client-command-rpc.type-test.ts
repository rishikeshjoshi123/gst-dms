import type { Database } from './database.types'

type CreateClient = Database['public']['Functions']['create_client_command']
type UpdateClient = Database['public']['Functions']['update_client_command']
type CreateResult = CreateClient['Returns'][number]
type UpdateResult = UpdateClient['Returns'][number]

const createArgs: CreateClient['Args'] = {
  p_name: 'Example Client', p_gstin: '', p_pan: '', p_idempotency_key: 'key',
}
const updateArgs: UpdateClient['Args'] = {
  p_client_id: 'client', p_expected_revision: 1, p_name: 'Example Client',
  p_gstin: '', p_pan: '', p_idempotency_key: 'key',
}
const nullableCreateId: string | null = null as CreateResult['client_id']
const nullableCreateRevision: number | null = null as CreateResult['revision']
const nullableUpdateId: string | null = null as UpdateResult['client_id']
const nullableUpdateRevision: number | null = null as UpdateResult['revision']

void createArgs
void updateArgs
void nullableCreateId
void nullableCreateRevision
void nullableUpdateId
void nullableUpdateRevision
