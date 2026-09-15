import assert from 'node:assert/strict'
import test from 'node:test'
import { currentMultiPreview, hasCurrentMultiMoveImpact, isCurrentMultiPreviewTicket, nextMultiPreviewTicket, type BoundMultiPreview, type MultiPreviewTicket } from './multi-preview-fence'

type Preview={code:string;fingerprint?:string;blockers?:string[];targetMatterTitle?:string}
function deferred<T>(){
  let resolve!: (value:T)=>void
  const promise=new Promise<T>(settle=>{resolve=settle})
  return {promise,resolve}
}

test('late A/B previews, Keep and unavailable target cannot carry impact into a different choice',async()=>{
  const itemA='review-item-a',itemB='review-item-b',targetA='matter-a',targetB='matter-b'
  let latest:MultiPreviewTicket={sequence:0,itemId:itemA,targetMatterId:null}
  let bound:BoundMultiPreview<Preview>|null=null
  let pending=false
  function select(itemId:string,targetMatterId:string|null,operation?:Promise<Preview>){
    const ticket=nextMultiPreviewTicket(latest,itemId,targetMatterId)
    latest=ticket;bound=null;pending=targetMatterId!==null
    if(!targetMatterId||!operation) return Promise.resolve()
    return operation.then(preview=>{
      if(!isCurrentMultiPreviewTicket(latest,ticket)) return
      bound={itemId,targetMatterId,preview};pending=false
    })
  }
  const aSlow=deferred<Preview>(),bFast=deferred<Preview>()
  const aTask=select(itemA,targetA,aSlow.promise)
  const bTask=select(itemA,targetB,bFast.promise)
  assert.equal(hasCurrentMultiMoveImpact(bound,itemA,targetB,pending),false)
  bFast.resolve({code:'ok',fingerprint:'b'.repeat(64),targetMatterTitle:'Matter B'})
  await bTask
  assert.equal(currentMultiPreview<Preview>(bound,itemA,targetB)?.targetMatterTitle,'Matter B')
  assert.equal(hasCurrentMultiMoveImpact(bound,itemA,targetB,pending),true)
  aSlow.resolve({code:'ok',fingerprint:'a'.repeat(64),targetMatterTitle:'Matter A'})
  await aTask
  assert.equal(currentMultiPreview<Preview>(bound,itemA,targetB)?.targetMatterTitle,'Matter B')
  assert.equal(currentMultiPreview(bound,itemA,targetA),null)

  const bSlow=deferred<Preview>(),aFast=deferred<Preview>()
  const bSlowTask=select(itemA,targetB,bSlow.promise)
  const aFastTask=select(itemA,targetA,aFast.promise)
  aFast.resolve({code:'ok',fingerprint:'a'.repeat(64),targetMatterTitle:'Matter A'})
  await aFastTask
  bSlow.resolve({code:'ok',fingerprint:'b'.repeat(64),targetMatterTitle:'Matter B'})
  await bSlowTask
  assert.equal(currentMultiPreview<Preview>(bound,itemA,targetA)?.targetMatterTitle,'Matter A')
  assert.equal(currentMultiPreview(bound,itemA,targetB),null)

  const cancelled=deferred<Preview>()
  const cancelledTask=select(itemA,targetA,cancelled.promise)
  await select(itemA,null)
  cancelled.resolve({code:'ok',fingerprint:'a'.repeat(64),targetMatterTitle:'Matter A'})
  await cancelledTask
  assert.equal(bound,null)
  assert.equal(pending,false)

  const unavailable=deferred<Preview>()
  const unavailableTask=select(itemA,targetB,unavailable.promise)
  assert.equal(currentMultiPreview(bound,itemA,targetB),null)
  unavailable.resolve({code:'failed'})
  await unavailableTask
  assert.equal(hasCurrentMultiMoveImpact(bound,itemA,targetB,pending),false)
  assert.equal(currentMultiPreview(bound,itemA,targetA),null)

  const otherItem=deferred<Preview>()
  const otherTask=select(itemB,targetA,otherItem.promise)
  otherItem.resolve({code:'ok',fingerprint:'c'.repeat(64),targetMatterTitle:'Other item A'})
  await otherTask
  assert.equal(currentMultiPreview(bound,itemA,targetA),null)
  assert.equal(currentMultiPreview<Preview>(bound,itemB,targetA)?.targetMatterTitle,'Other item A')
})
