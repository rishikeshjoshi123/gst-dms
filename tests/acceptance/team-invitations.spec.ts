import { expect,test,type APIRequestContext,type Page } from '@playwright/test'

type CapturedMessage={to:string;subject:string;html:string}
const captureUrl='http://127.0.0.1:3261/messages'

async function login(page:Page,email='owner@acceptance.test'){await page.goto('/login');await page.getByLabel('Email address').fill(email);await page.getByLabel('Password').fill('CaseChain-local-only-2026!');await page.getByRole('button',{name:'Sign in'}).click();await expect(page).toHaveURL(/\/dashboard$/)}
async function waitForMessages(request:APIRequestContext,email:string,count:number){let matches:CapturedMessage[]=[];await expect.poll(async()=>{const response=await request.get(captureUrl);if(!response.ok())return 0;const messages=await response.json() as CapturedMessage[];matches=messages.filter(message=>message.to===email);return matches.length}).toBe(count);return matches}
function invitationToken(message:CapturedMessage){return message.html.match(/\/api\/invites\/accept\?token=([^"&<\s]+)/)?.[1]}

test.describe.serial('Team invitation administration',()=>{
 test('Owner creates, resends, and revokes a captured invitation',async({page,request})=>{
  const recipient='browser-created-invite@acceptance.test'
  await page.setViewportSize({width:1440,height:900});await login(page);await page.goto('/team')
  await expect(page.getByRole('tab',{name:'Members'})).toHaveAttribute('aria-selected','true')
  await page.getByRole('tab',{name:'Invitations'}).click();await expect(page).toHaveURL(/view=invitations/)
  await expect(page.getByRole('cell',{name:'pending-colleague-with-a-very-long-address@acceptance.test'})).toBeVisible()
  await expect(page.getByText('revoked@acceptance.test')).toHaveCount(0)
  await page.getByRole('button',{name:'Invite member'}).click()
  await expect(page.getByRole('dialog')).toContainText('Choose access before sending')
  await expect(page.getByRole('button',{name:/Admin · Owner only/})).toBeVisible()
  await page.getByLabel('Work email').fill(recipient)
  await page.getByRole('button',{name:'Send invitation'}).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.getByText('Invitation sent.')).toBeVisible()
  const firstMessages=await waitForMessages(request,recipient,1)
  const firstToken=invitationToken(firstMessages[0])
  expect(Boolean(firstToken)&&firstMessages[0].html.includes('/api/invites/accept?token=')).toBe(true)
  const pendingRow=page.getByRole('row').filter({hasText:recipient})
  await expect(pendingRow).toBeVisible()
  await pendingRow.getByRole('button',{name:'Resend',exact:true}).click()
  await expect(page.getByText('Invitation resent with a new seven-day expiry.')).toBeVisible()
  const resentMessages=await waitForMessages(request,recipient,2)
  const secondToken=invitationToken(resentMessages[1])
  expect(Boolean(secondToken)&&secondToken!==firstToken).toBe(true)
  const renewedRow=page.getByRole('row').filter({hasText:recipient})
  await expect(renewedRow).toBeVisible()
  await renewedRow.getByRole('button',{name:'Revoke',exact:true}).click()
  await expect(page.getByRole('dialog',{name:'Revoke invitation?'})).toContainText(recipient)
  await page.getByRole('button',{name:'Revoke invitation',exact:true}).click()
  await expect(page.getByText('Invitation revoked.')).toBeVisible()
  await expect(page.getByRole('row').filter({hasText:recipient})).toHaveCount(0)
  await page.getByLabel('Invitation status').selectOption('revoked')
  await expect(page.getByRole('cell',{name:recipient})).toBeVisible()
  await expect(page.getByRole('cell',{name:'revoked@acceptance.test'})).toBeVisible()
  await expect(page.getByRole('button',{name:/Resend/})).toHaveCount(0)
 })
 test('320px dark keyboard presentation retains actions without overflow',async({page})=>{
  await page.setViewportSize({width:320,height:800});await login(page);await page.evaluate(()=>localStorage.setItem('theme','dark'));await page.goto('/team?view=invitations')
  await expect(page.locator('html')).toHaveClass(/\bdark\b/)
  const invite=page.getByRole('button',{name:'Invite member'});await invite.focus();await expect(invite).toBeFocused();await page.keyboard.press('Enter');await expect(page.getByRole('dialog')).toBeVisible();await page.keyboard.press('Escape');await expect(invite).toBeFocused()
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBeLessThanOrEqual(1)
  const resend=page.getByRole('button',{name:'Resend invitation'});const box=await resend.boundingBox();expect(box).not.toBeNull();const pseudo=await resend.evaluate(element=>{const style=getComputedStyle(element,'::before');return{width:Number.parseFloat(style.width)||0,height:Number.parseFloat(style.height)||0}});expect(Math.max(box?.width??0,pseudo.width)).toBeGreaterThanOrEqual(43.9);expect(Math.max(box?.height??0,pseudo.height)).toBeGreaterThanOrEqual(43.9)
 })
 test('Viewer sees Members but no invitation administration',async({page})=>{
  await login(page,'viewer@acceptance.test');await page.goto('/team?view=invitations');await expect(page.getByRole('tab',{name:'Members'})).toBeVisible();await expect(page.getByRole('tab',{name:'Members'})).toHaveAttribute('aria-selected','true');await expect(page.getByRole('tab',{name:'Invitations'})).toHaveCount(0);await expect(page.getByRole('button',{name:'Invite member'})).toHaveCount(0);await expect(page.getByLabel('Role')).toBeVisible()
 })
})
