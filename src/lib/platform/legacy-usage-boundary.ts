export function isLegacyUsageDevelopmentEnvironment(
  environment = process.env.NODE_ENV,
): boolean {
  return environment === 'development'
}
