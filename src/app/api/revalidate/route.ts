import { revalidatePath } from 'next/cache'
import { NextResponse } from 'next/server'

export async function POST(request: Request) {
  try {
    const { paths, secret } = await request.json()

    // Replace this with your actual app secret stored in environment variables
    if (secret !== process.env.API_SECRET_KEY) {
      return NextResponse.json({ message: 'Invalid token' }, { status: 401 })
    }

    if (!paths || !Array.isArray(paths)) {
      return NextResponse.json({ message: 'Missing or invalid paths array' }, { status: 400 })
    }

    for (const path of paths) {
      revalidatePath(path)
    }

    return NextResponse.json({ revalidated: true, now: Date.now() })
  } catch (err) {
    return NextResponse.json({ message: 'Error revalidating' }, { status: 500 })
  }
}
