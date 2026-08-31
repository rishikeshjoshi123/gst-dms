'use client'

import Image from 'next/image'
import { useEffect, useRef } from 'react'

interface LandingParallaxImageProps {
  src: string
  alt: string
  sizes: string
  className?: string
  speed?: number
  preload?: boolean
  loading?: 'eager' | 'lazy'
  unoptimized?: boolean
}

export function LandingParallaxImage({
  src,
  alt,
  sizes,
  className,
  speed = 0.045,
  preload,
  loading,
  unoptimized,
}: LandingParallaxImageProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const imageRef = useRef<HTMLImageElement>(null)

  useEffect(() => {
    const container = containerRef.current
    const image = imageRef.current
    const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce), (max-width: 767px)')

    if (!container || !image) return

    let animationFrame = 0

    const updatePosition = () => {
      animationFrame = 0
      const rect = container.getBoundingClientRect()

      if (rect.bottom < 0 || rect.top > window.innerHeight) return

      const viewportCenter = window.innerHeight / 2
      const imageCenter = rect.top + rect.height / 2
      const offset = Math.max(-36, Math.min(36, (viewportCenter - imageCenter) * speed))
      image.style.transform = `translate3d(0, ${offset}px, 0) scale(1.08)`
    }

    const requestUpdate = () => {
      if (!animationFrame) animationFrame = window.requestAnimationFrame(updatePosition)
    }

    const syncMotionPreference = () => {
      if (motionQuery.matches) {
        window.removeEventListener('scroll', requestUpdate)
        window.removeEventListener('resize', requestUpdate)
        image.style.removeProperty('transform')
        return
      }

      window.addEventListener('scroll', requestUpdate, { passive: true })
      window.addEventListener('resize', requestUpdate)
      requestUpdate()
    }

    motionQuery.addEventListener('change', syncMotionPreference)
    syncMotionPreference()

    return () => {
      motionQuery.removeEventListener('change', syncMotionPreference)
      window.removeEventListener('scroll', requestUpdate)
      window.removeEventListener('resize', requestUpdate)
      if (animationFrame) window.cancelAnimationFrame(animationFrame)
      image.style.removeProperty('transform')
    }
  }, [speed])

  return (
    <div ref={containerRef} className="absolute inset-0 overflow-hidden" aria-hidden={alt ? undefined : true}>
      <Image
        ref={imageRef}
        src={src}
        alt={alt}
        fill
        preload={preload}
        loading={loading}
        unoptimized={unoptimized}
        sizes={sizes}
        className={`object-cover will-change-transform motion-reduce:transform-none md:scale-[1.08] ${className ?? ''}`}
      />
    </div>
  )
}
