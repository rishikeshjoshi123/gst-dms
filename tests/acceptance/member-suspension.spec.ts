import { expect,test,type Page } from '@playwright/test'

const password='CaseChain-local-only-2026!'
async function login(page:Page,email:string,expected=/\/dashboard$/){await page.goto('/login');await page.getByLabel('Email address').fill(email);await page.getByLabel('Password').fill(password);await page.getByRole('button',{name:'Sign in'}).click();await expect(page).toHaveURL(expected)}
async function inspect(page:Page,name:string){await page.goto(`/team?q=${encodeURIComponent(name)}`);await page.getByRole('button',{name:new RegExp(name)}).first().click();await expect(page.getByRole('heading',{name})).toBeVisible()}
async function suspendVisibleMember(page:Page,reason:string,count:number){await page.getByRole('button',{name:'Preview suspension'}).click();const dialog=page.getByRole('dialog');await expect(dialog).toContainText(`${count} open or in-progress task`);await dialog.getByLabel('Reason for suspension').fill(reason);await dialog.getByRole('checkbox').check();await dialog.getByRole('button',{name:'Suspend access and return tasks'}).click();await expect(dialog).toHaveCount(0);await expect(page.getByRole('complementary',{name:'Member details'}).getByText('Suspended',{exact:true})).toBeVisible()}

test.describe.serial('governed member suspension',()=>{
 test('Owner suspends and an existing target session loses its next protected request',async({browser,page})=>{
  const targetContext=await browser.newContext();const target=await targetContext.newPage();await login(target,'suspend-owner-target@acceptance.test');
  await login(page,'owner@acceptance.test');await inspect(page,'Owner Suspension Target');await suspendVisibleMember(page,'Owner browser access review',1)
  await expect(page.getByRole('heading',{name:'Owner Suspension Target'})).toBeFocused()
  await target.getByRole('link',{name:'Team'}).click();await expect(target).toHaveURL(/\/onboarding$/);await expect(target.getByRole('heading',{name:'Access suspended'})).toBeVisible()
  await target.getByRole('button',{name:'Log out'}).click();await login(target,'suspend-owner-target@acceptance.test',/\/onboarding$/);await expect(target.getByRole('heading',{name:'Access suspended'})).toBeVisible();await targetContext.close()
 })
 test('Admin can suspend an ordinary Viewer',async({page})=>{await login(page,'admin@acceptance.test');await inspect(page,'Admin Suspension Target');await suspendVisibleMember(page,'Admin browser access review',0)})
 test('Viewer has no suspension control',async({page})=>{await login(page,'suspension-viewer@acceptance.test');await inspect(page,'Mobile Suspension Target');await expect(page.getByRole('button',{name:'Preview suspension'})).toHaveCount(0)})
 test('320px dark keyboard flow owns overflow, touch targets, dialog return, and success focus',async({page})=>{
  await page.setViewportSize({width:320,height:800});await login(page,'owner@acceptance.test');await page.evaluate(()=>localStorage.setItem('theme','dark'));await inspect(page,'Mobile Suspension Target');await expect(page.locator('html')).toHaveClass(/\bdark\b/)
  const trigger=page.getByRole('button',{name:'Preview suspension'});await trigger.focus();await page.keyboard.press('Enter');const dialog=page.getByRole('dialog');await expect(dialog).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBeLessThanOrEqual(1)
  const confirm=dialog.getByRole('button',{name:'Suspend access and return tasks'});const box=await confirm.boundingBox();expect(box?.height??0).toBeGreaterThanOrEqual(43.9);await page.keyboard.press('Escape');await expect(trigger).toBeFocused()
  await page.keyboard.press('Enter');await dialog.getByLabel('Reason for suspension').fill('Mobile keyboard access review');await dialog.getByRole('checkbox').check();await confirm.click();await expect(dialog).toHaveCount(0);await expect(page.getByRole('heading',{name:'Mobile Suspension Target'})).toBeFocused();expect(await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth)).toBeLessThanOrEqual(1)
 })
})
