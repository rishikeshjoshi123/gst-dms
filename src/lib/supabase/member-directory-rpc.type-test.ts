import type { Database } from './database.types'

type DirectoryRow = Database['public']['Functions']['get_my_team_members']['Returns'][number]

const userId: string = '' as DirectoryRow['user_id']
const email: string | null = null as DirectoryRow['authorised_email']
const displayName: string | null = null as DirectoryRow['display_name']
const professionalTitle: string | null = null as DirectoryRow['professional_title']

void userId
void email
void displayName
void professionalTitle
