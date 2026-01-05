/**
 * Custom ESLint rules for the project.
 */

import noConsecutiveLogging from './no-consecutive-logging.mjs';

export default {
  rules: {
    'no-consecutive-logging': noConsecutiveLogging,
  },
};

