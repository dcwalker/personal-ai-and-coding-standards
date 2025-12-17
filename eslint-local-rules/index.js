/**
 * Custom ESLint rules for the project.
 */

import noConsecutiveLogging from './no-consecutive-logging.js';

export default {
  rules: {
    'no-consecutive-logging': noConsecutiveLogging,
  },
};

