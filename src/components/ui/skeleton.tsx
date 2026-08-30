import { cn } from '@/lib/utils'

export type SkeletonProps = React.HTMLAttributes<HTMLSpanElement>

function Skeleton({ className, ...props }: SkeletonProps) {
  return (
    <span
      className={cn('skeleton block', className)}
      {...props}
      aria-hidden="true"
    />
  )
}

export { Skeleton }
