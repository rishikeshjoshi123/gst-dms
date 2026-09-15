import { revalidatePath } from 'next/cache'
import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  try {
    const { paths, secret } = await request.json()

    const configuredSecret = process.env.API_SECRET_KEY
    if (typeof configuredSecret !== 'string' || configuredSecret.trim().length === 0 ||
        typeof secret !== 'string' || secret.length === 0 || secret !== configuredSecret) {
      return NextResponse.json({ message: 'Invalid token' }, { status: 401 })
    }

    if (!paths || !Array.isArray(paths)) {
      return NextResponse.json({ message: 'Missing or invalid paths array' }, { status: 400 })
    }

    for (const path of paths) {
      revalidatePath(path)
    }

    return NextResponse.json({ revalidated: true, now: Date.now() })
  } catch {
    return NextResponse.json({ message: 'Error revalidating' }, { status: 500 })
  }
}
