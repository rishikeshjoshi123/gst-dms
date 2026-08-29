export function formatInrDecimal(value: string): string {
  const [integerPart, fraction] = value.split('.')
  const negative = integerPart.startsWith('-')
  const digits = negative ? integerPart.slice(1) : integerPart
  const tail = digits.slice(-3)
  const head = digits.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ',')
  return `₹${negative ? '-' : ''}${head ? `${head},` : ''}${tail}${fraction === undefined ? '' : `.${fraction}`}`
}
