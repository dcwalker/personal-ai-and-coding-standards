/**
 * ESLint rule to prevent consecutive logging statements.
 * Consecutive log calls should be consolidated into a single log message
 * using newlines for formatting.
 *
 * This rule flags logging statements that appear consecutively without any
 * executable code between them, regardless of whether they use different log
 * levels (e.g., info followed by warn).
 *
 * Comments and whitespace are ignored. The rule only resets when it encounters
 * actual executable code between logging statements.
 */

export default {
  meta: {
    type: 'problem',
    docs: {
      description: 'Disallow consecutive logging statements',
      category: 'Best Practices',
      recommended: true,
    },
    messages: {
      consecutiveLogs:
        'Consecutive logging statements detected. Consolidate into a single log message using newlines (\\n) for formatting.',
    },
    schema: [],
  },

  /**
   * Creates the ESLint rule visitor object
   * @returns {object} ESLint rule visitor methods
   */
  create(context) {
    /**
     * Check if a node is a logging statement
     * @returns {boolean} True if the node is a logging statement
     */
    function isLoggingStatement(node) {
      if (node.type !== 'ExpressionStatement') {
        return false;
      }

      const expression = node.expression;
      if (expression.type !== 'CallExpression') {
        return false;
      }

      const callee = expression.callee;
      if (callee.type !== 'MemberExpression') {
        return false;
      }

      // Check if the object is 'logger' or 'console'
      const objectName =
        callee.object.type === 'Identifier' ? callee.object.name : null;
      if (
        !objectName ||
        (objectName !== 'logger' && objectName !== 'console')
      ) {
        return false;
      }

      // Check if the method is a logging method
      const methodName =
        callee.property.type === 'Identifier' ? callee.property.name : null;
      const loggingMethods = ['log', 'info', 'warn', 'error', 'debug', 'trace'];

      return loggingMethods.includes(methodName);
    }

    /**
     * Check a body of statements for consecutive logging
     * @returns {void} No return value
     */
    function checkBody(body) {
      if (!body || !Array.isArray(body)) {
        return;
      }

      let previousLoggingStatement = null;

      for (const statement of body) {
        if (isLoggingStatement(statement)) {
          if (previousLoggingStatement) {
            context.report({
              node: statement,
              messageId: 'consecutiveLogs',
              loc: statement.loc,
            });
          }
          previousLoggingStatement = statement;
        } else {
          // Any other statement type resets the tracking
          previousLoggingStatement = null;
        }
      }
    }

    return {
      /**
       * Checks the program body for consecutive logging
       * @returns {void} No return value
       */
      Program(node) {
        checkBody(node.body);
      },
      /**
       * Checks block statements for consecutive logging
       * @returns {void} No return value
       */
      BlockStatement(node) {
        checkBody(node.body);
      },
      /**
       * Checks switch cases for consecutive logging
       * @returns {void} No return value
       */
      SwitchCase(node) {
        checkBody(node.consequent);
      },
    };
  },
};

