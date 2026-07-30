import { getRecentActivityLogs } from './src/lib/actions/notifications';
(async () => {
  const logs = await getRecentActivityLogs();
  console.log(JSON.stringify(logs.slice(0, 5), null, 2));
})();
