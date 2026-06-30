import { Resend } from 'resend'

const resend = new Resend(process.env.RESEND_API_KEY)

const FROM = process.env.RESEND_FROM_EMAIL ?? 'noreply@gst-dms.app'

/**
 * Guard: skip sending real emails outside production.
 * Supabase local dev captures auth emails in Inbucket at localhost:54324.
 */
function isProduction() {
  return process.env.NODE_ENV === 'production'
}

export interface EmailResult {
  success: boolean
  id?: string
  error?: string
}

async function sendEmail(options: {
  to: string | string[]
  subject: string
  html: string
}): Promise<EmailResult> {
  if (!isProduction()) {
    console.log('[Email skipped in dev]', {
      to: options.to,
      subject: options.subject,
    })
    return { success: true, id: 'dev-skipped' }
  }

  try {
    const { data, error } = await resend.emails.send({
      from: FROM,
      to: options.to,
      subject: options.subject,
      html: options.html,
    })

    if (error) {
      console.error('[Resend error]', error)
      return { success: false, error: error.message }
    }

    return { success: true, id: data?.id }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    console.error('[Resend exception]', message)
    return { success: false, error: message }
  }
}

// ================================================================
// Email templates
// ================================================================

export async function sendOrgInviteEmail(options: {
  to: string
  orgName: string
  /** Legacy: pass full invite URL directly */
  inviteUrl?: string
  /** New: pass inviter name + token + appUrl */
  inviterName?: string
  inviteToken?: string
  appUrl?: string
  /** Legacy param name support */
  invitedByName?: string
}): Promise<EmailResult> {
  const inviterDisplay = options.inviterName ?? options.invitedByName ?? 'A team member'
  const acceptUrl = options.inviteUrl
    ?? `${options.appUrl}/api/invites/accept?token=${options.inviteToken}`

  return sendEmail({
    to: options.to,
    subject: `You've been invited to join ${options.orgName} on GST DMS`,
    html: `
      <div style="font-family: Inter, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
        <h1 style="color: #1a1a2e; font-size: 24px; margin-bottom: 8px;">You're invited!</h1>
        <p style="color: #4a4a6a; font-size: 16px; line-height: 1.6;">
          <strong>${inviterDisplay}</strong> has invited you to join
          <strong>${options.orgName}</strong> on GST DMS.
        </p>
        <div style="margin: 32px 0;">
          <a href="${acceptUrl}"
             style="background: #4f46e5; color: white; padding: 12px 24px; border-radius: 8px;
                    text-decoration: none; font-weight: 600; display: inline-block;">
            Accept Invitation
          </a>
        </div>
        <p style="color: #9a9ab0; font-size: 14px;">
          This invitation expires in 7 days. If you didn't expect this, you can safely ignore it.
        </p>
      </div>
    `,
  })
}


export async function sendDeadlineReminderEmail(options: {
  to: string
  userName: string
  matterTitle: string
  deadlineDescription: string
  dueDate: string
  daysRemaining: number
  matterUrl: string
}): Promise<EmailResult> {
  const urgencyColor = options.daysRemaining <= 7 ? '#dc2626' : '#d97706'

  return sendEmail({
    to: options.to,
    subject: `⚠️ Deadline in ${options.daysRemaining} days — ${options.matterTitle}`,
    html: `
      <div style="font-family: Inter, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
        <div style="background: ${urgencyColor}; color: white; padding: 12px 20px; border-radius: 8px; margin-bottom: 24px;">
          <strong>⚠️ ${options.daysRemaining} day${options.daysRemaining !== 1 ? 's' : ''} remaining</strong>
        </div>
        <h1 style="color: #1a1a2e; font-size: 22px;">${options.deadlineDescription}</h1>
        <p style="color: #4a4a6a;">
          Matter: <strong>${options.matterTitle}</strong><br/>
          Due: <strong>${options.dueDate}</strong>
        </p>
        <a href="${options.matterUrl}"
           style="background: #4f46e5; color: white; padding: 12px 24px; border-radius: 8px;
                  text-decoration: none; font-weight: 600; display: inline-block; margin-top: 16px;">
          View Matter
        </a>
      </div>
    `,
  })
}

export async function sendMentionEmail(options: {
  to: string
  mentionedByName: string
  notePreview: string
  matterTitle: string
  noteUrl: string
}): Promise<EmailResult> {
  return sendEmail({
    to: options.to,
    subject: `${options.mentionedByName} mentioned you in a note`,
    html: `
      <div style="font-family: Inter, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
        <h1 style="color: #1a1a2e; font-size: 22px;">You were mentioned</h1>
        <p style="color: #4a4a6a;">
          <strong>${options.mentionedByName}</strong> mentioned you in a note on
          <strong>${options.matterTitle}</strong>:
        </p>
        <blockquote style="border-left: 4px solid #4f46e5; padding-left: 16px; color: #4a4a6a;
                           font-style: italic; margin: 16px 0;">
          "${options.notePreview}"
        </blockquote>
        <a href="${options.noteUrl}"
           style="background: #4f46e5; color: white; padding: 12px 24px; border-radius: 8px;
                  text-decoration: none; font-weight: 600; display: inline-block;">
          View Note
        </a>
      </div>
    `,
  })
}
