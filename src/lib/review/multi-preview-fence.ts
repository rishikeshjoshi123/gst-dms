export type MultiPreviewTicket={sequence:number;itemId:string;targetMatterId:string|null}
export type BoundMultiPreview<T>={itemId:string;targetMatterId:string;preview:T}

export function nextMultiPreviewTicket(current:MultiPreviewTicket,itemId:string,targetMatterId:string|null):MultiPreviewTicket{
  return {sequence:current.sequence+1,itemId,targetMatterId}
}

export function isCurrentMultiPreviewTicket(current:MultiPreviewTicket,request:MultiPreviewTicket):boolean{
  return current.sequence===request.sequence&&current.itemId===request.itemId
    &&current.targetMatterId===request.targetMatterId
}

export function currentMultiPreview<T>(bound:BoundMultiPreview<T>|null,itemId:string,choice:string):T|null{
  return bound?.itemId===itemId&&bound.targetMatterId===choice?bound.preview:null
}

export function hasCurrentMultiMoveImpact(
  bound:BoundMultiPreview<{code:string;fingerprint?:string;blockers?:readonly unknown[]}>|null,
  itemId:string,choice:string,pending:boolean,
):boolean{
  const preview=currentMultiPreview(bound,itemId,choice)
  return !pending&&preview?.code==='ok'&&!!preview.fingerprint&&!preview.blockers?.length
}
