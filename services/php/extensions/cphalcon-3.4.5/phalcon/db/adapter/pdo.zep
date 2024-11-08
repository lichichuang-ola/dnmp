
/*
 +------------------------------------------------------------------------+
 | Phalcon Framework                                                      |
 +------------------------------------------------------------------------+
 | Copyright (c) 2011-2017 Phalcon Team (https://phalconphp.com)          |
 +------------------------------------------------------------------------+
 | This source file is subject to the New BSD License that is bundled     |
 | with this package in the file LICENSE.txt.                             |
 |                                                                        |
 | If you did not receive a copy of the license and are unable to         |
 | obtain it through the world-wide-web, please send an email             |
 | to license@phalconphp.com so we can send you a copy immediately.       |
 +------------------------------------------------------------------------+
 | Authors: Andres Gutierrez <andres@phalconphp.com>                      |
 |          Eduar Carvajal <eduar@phalconphp.com>                         |
 +------------------------------------------------------------------------+
 */

namespace Phalcon\Db\Adapter;

use Phalcon\Db\Adapter;
use Phalcon\Db\Exception;
use Phalcon\Db\Column;
use Phalcon\Db\ResultInterface;
use Phalcon\Events\ManagerInterface;
use Phalcon\Db\Result\Pdo as ResultPdo;

/**
 * Phalcon\Db\Adapter\Pdo
 *
 * Phalcon\Db\Adapter\Pdo is the Phalcon\Db that internally uses PDO to connect to a database
 *
 * <code>
 * use Phalcon\Db\Adapter\Pdo\Mysql;
 *
 * $config = [
 *     "host"     => "localhost",
 *     "dbname"   => "blog",
 *     "port"     => 3306,
 *     "username" => "sigma",
 *     "password" => "secret",
 * ];
 *
 * $connection = new Mysql($config);
 *</code>
 */
abstract class Pdo extends Adapter
{

	/**
	 * PDO Handler
	 *
	 * @var \Pdo
	 */
	protected _pdo;

	/**
	 * Last affected rows
	 */
	protected _affectedRows;

	/**
	 * Constructor for Phalcon\Db\Adapter\Pdo
	 */
	public function __construct(array! descriptor)
	{
		this->connect(descriptor);
		parent::__construct(descriptor);
	}

	/**
	 * This method is automatically called in \Phalcon\Db\Adapter\Pdo constructor.
	 *
	 * Call it when you need to restore a database connection.
	 *
	 *<code>
	 * use Phalcon\Db\Adapter\Pdo\Mysql;
	 *
	 * // Make a connection
	 * $connection = new Mysql(
	 *     [
	 *         "host"     => "localhost",
	 *         "username" => "sigma",
	 *         "password" => "secret",
	 *         "dbname"   => "blog",
	 *         "port"     => 3306,
	 *     ]
	 * );
	 *
	 * // Reconnect
	 * $connection->connect();
	 * </code>
	 */
	public function connect(array descriptor = null) -> boolean
	{
		var username, password, dsnParts, dsnAttributes,
			persistent, options, key, value;

		if empty descriptor {
			let descriptor = (array) this->_descriptor;
		}

		/**
		 * Check for a username or use null as default
		 */
		if fetch username, descriptor["username"] {
			unset descriptor["username"];
		} else {
			let username = null;
		}

		/**
		 * Check for a password or use null as default
		 */
		if fetch password, descriptor["password"] {
			unset descriptor["password"];
		} else {
			let password = null;
		}

		/**
		 * Check if the developer has defined custom options or create one from scratch
		 */
		if fetch options, descriptor["options"] {
			unset descriptor["options"];
		} else {
			let options = [];
		}

		/**
		 * Check for \PDO::XXX class constant aliases
		 */
        for key, value in options {
            if typeof key == "string" && defined("\PDO::" . strtoupper(key)) {
                let options[constant("\PDO::" . strtoupper(key))] = value;
                unset options[key];
            }
        }

		/**
		 * Check if the connection must be persistent
		 */
		if fetch persistent, descriptor["persistent"] {
			if persistent {
				let options[\Pdo::ATTR_PERSISTENT] = true;
			}
			unset descriptor["persistent"];
		}

		/**
		 * Remove the dialectClass from the descriptor if any
		 */
		if isset descriptor["dialectClass"] {
			unset descriptor["dialectClass"];
		}

		/**
		 * Check if the user has defined a custom dsn
		 */
		 if !fetch dsnAttributes, descriptor["dsn"] {
			let dsnParts = [];
			for key, value in descriptor {
				let dsnParts[] = key . "=" . value;
			}
			let dsnAttributes = join(";", dsnParts);
		}

		let options[\Pdo::ATTR_ERRMODE] = \Pdo::ERRMODE_EXCEPTION;

		/**
		 * Create the connection using PDO
		 */
		let this->_pdo = new \Pdo(this->_type . ":" . dsnAttributes, username, password, options);

		return true;
	}

	/**
	 * Returns a PDO prepared statement to be executed with 'executePrepared'
	 *
	 *<code>
	 * use Phalcon\Db\Column;
	 *
	 * $statement = $db->prepare(
	 *     "SELECT * FROM robots WHERE name = :name"
	 * );
	 *
	 * $result = $connection->executePrepared(
	 *     $statement,
	 *     [
	 *         "name" => "Voltron",
	 *     ],
	 *     [
	 *         "name" => Column::BIND_PARAM_INT,
	 *     ]
	 * );
	 *</code>
	 */
	public function prepare(string! sqlStatement) -> <\PDOStatement>
	{
		return this->_pdo->prepare(sqlStatement);
	}

	/**
	 * Executes a prepared statement binding. This function uses integer indexes starting from zero
	 *
	 *<code>
	 * use Phalcon\Db\Column;
	 *
	 * $statement = $db->prepare(
	 *     "SELECT * FROM robots WHERE name = :name"
	 * );
	 *
	 * $result = $connection->executePrepared(
	 *     $statement,
	 *     [
	 *         "name" => "Voltron",
	 *     ],
	 *     [
	 *         "name" => Column::BIND_PARAM_INT,
	 *     ]
	 * );
	 *</code>
	 *
	 * @param \PDOStatement statement
	 * @param array placeholders
	 * @param array dataTypes
	 * @return \PDOStatement
	 */
	public function executePrepared(<\PDOStatement> statement, array! placeholders, dataTypes) -> <\PDOStatement>
	{
		var wildcard, value, type, castValue,
			parameter, position, itemValue;

		for wildcard, value in placeholders {

			if typeof wildcard == "integer" {
				let parameter = wildcard + 1;
			} elseif typeof wildcard == "string" {
				let parameter = wildcard;
			} else {
				throw new Exception("Invalid bind parameter (1)");
			}

			if typeof dataTypes == "array" && fetch type, dataTypes[wildcard] {

				/**
				 * The bind type is double so we try to get the double value
				 */
				if type == Column::BIND_PARAM_DECIMAL {
					let castValue = doubleval(value),
						type = Column::BIND_SKIP;
				} else {
					if globals_get("db.force_casting") {
						if typeof value != "array" {
							switch type {

								case Column::BIND_PARAM_INT:
									let castValue = intval(value, 10);
									break;

								case Column::BIND_PARAM_STR:
									let castValue = (string) value;
									break;

								case Column::BIND_PARAM_NULL:
									let castValue = null;
									break;

								case Column::BIND_PARAM_BOOL:
									let castValue = (boolean) value;
									break;

								default:
									let castValue = value;
									break;
							}
						} else {
							let castValue = value;
						}
					} else {
						let castValue = value;
					}
				}

				/**
				 * 1024 is ignore the bind type
				 */
				if typeof castValue != "array" {
					if type == Column::BIND_SKIP {
						statement->bindValue(parameter, castValue);
					} else {
						statement->bindValue(parameter, castValue, type);
					}
				} else {
					for position, itemValue in castValue {
						if type == Column::BIND_SKIP {
							statement->bindValue(parameter . position, itemValue);
						} else {
							statement->bindValue(parameter . position, itemValue, type);
						}
					}
				}
			} else {
				if typeof value != "array" {
					statement->bindValue(parameter, value);
				} else {
					for position, itemValue in value {
						statement->bindValue(parameter . position, itemValue);
					}
				}
			}
		}

		statement->execute();
		return statement;
	}

	/**
	 * Sends SQL statements to the database server returning the success state.
	 * Use this method only when the SQL statement sent to the server is returning rows
	 *
	 *<code>
	 * // Querying data
	 * $resultset = $connection->query(
	 *     "SELECT * FROM robots WHERE type = 'mechanical'"
	 * );
	 *
	 * $resultset = $connection->query(
	 *     "SELECT * FROM robots WHERE type = ?",
	 *     [
	 *         "mechanical",
	 *     ]
	 * );
	 *</code>
	 */
	public function query(string! sqlStatement, var bindParams = null, var bindTypes = null) -> <ResultInterface> | boolean
	{
		var eventsManager, pdo, statement, params, types;

		let eventsManager = <ManagerInterface> this->_eventsManager;

		/**
		 * Execute the beforeQuery event if an EventsManager is available
		 */
		if typeof eventsManager == "object" {
			let this->_sqlStatement = sqlStatement,
				this->_sqlVariables = bindParams,
				this->_sqlBindTypes = bindTypes;
			if eventsManager->fire("db:beforeQuery", this) === false {
				return false;
			}
		}

		let pdo = <\Pdo> this->_pdo;
		if typeof bindParams == "array" {
			let params = bindParams;
			let types = bindTypes;
		} else {
			let params = [];
			let types = [];
		}

		let statement = pdo->prepare(sqlStatement);
		if typeof statement == "object" {
			let statement = this->executePrepared(statement, params, types);
		} else {
			throw new Exception("Cannot prepare statement");
		}

		/**
		 * Execute the afterQuery event if an EventsManager is available
		 */
		if typeof statement == "object" {
			if typeof eventsManager == "object" {
				eventsManager->fire("db:afterQuery", this);
			}
			return new ResultPdo(this, statement, sqlStatement, bindParams, bindTypes);
		}

		return statement;
	}

	/**
	 * Sends SQL statements to the database server returning the success state.
	 * Use this method only when the SQL statement sent to the server doesn't return any rows
	 *
	 *<code>
	 * // Inserting data
	 * $success = $connection->execute(
	 *     "INSERT INTO robots VALUES (1, 'Astro Boy')"
	 * );
	 *
	 * $success = $connection->execute(
	 *     "INSERT INTO robots VALUES (?, ?)",
	 *     [
	 *         1,
	 *         "Astro Boy",
	 *     ]
	 * );
	 *</code>
	 */
	public function execute(string! sqlStatement, var bindParams = null, var bindTypes = null) -> boolean
	{
		var eventsManager, affectedRows, pdo, newStatement, statement;

		/**
		 * Execute the beforeQuery event if an EventsManager is available
		 */
		let eventsManager = <ManagerInterface> this->_eventsManager;
		if typeof eventsManager == "object" {
			let this->_sqlStatement = sqlStatement,
				this->_sqlVariables = bindParams,
				this->_sqlBindTypes = bindTypes;
			if eventsManager->fire("db:beforeQuery", this) === false {
				return false;
			}
		}

		/**
		 * Initialize affectedRows to 0
		 */
		let affectedRows = 0;

		let pdo = <\Pdo> this->_pdo;
		if typeof bindParams == "array" {
			let statement = pdo->prepare(sqlStatement);
			if typeof statement == "object" {
				let newStatement = this->executePrepared(statement, bindParams, bindTypes),
					affectedRows = newStatement->rowCount();
			}
		} else {
			let affectedRows = pdo->exec(sqlStatement);
		}

		/**
		 * Execute the afterQuery event if an EventsManager is available
		 */
		if typeof affectedRows == "integer" {
			let this->_affectedRows = affectedRows;
			if typeof eventsManager == "object" {
				eventsManager->fire("db:afterQuery", this);
			}
		}

		return true;
	}

	/**
	 * Returns the number of affected rows by the latest INSERT/UPDATE/DELETE executed in the database system
	 *
	 *<code>
	 * $connection->execute(
	 *     "DELETE FROM robots"
	 * );
	 *
	 * echo $connection->affectedRows(), " were deleted";
	 *</code>
	 */
	public function affectedRows() -> int
	{
		return this->_affectedRows;
	}

	/**
	 * Closes the active connection returning success. Phalcon automatically closes and destroys
	 * active connections when the request ends
	 */
	public function close() -> boolean
	{
		var pdo;
		let pdo = this->_pdo;
		if typeof pdo == "object" {
			let this->_pdo = null;
		}
		return true;
	}

	/**
	 * Escapes a value to avoid SQL injections according to the active charset in the connection
	 *
	 *<code>
	 * $escapedStr = $connection->escapeString("some dangerous value");
	 *</code>
	 */
	public function escapeString(string str) -> string
	{
		return this->_pdo->quote(str);
	}

	/**
	 * Converts bound parameters such as :name: or ?1 into PDO bind params ?
	 *
	 *<code>
	 * print_r(
	 *     $connection->convertBoundParams(
	 *         "SELECT * FROM robots WHERE name = :name:",
	 *         [
	 *             "Bender",
	 *         ]
	 *     )
	 * );
	 *</code>
	 */
	public function convertBoundParams(string! sql, array params = []) -> array
	{
		var boundSql, placeHolders, bindPattern, matches,
			setOrder, placeMatch, value;

		let placeHolders = [],
			bindPattern = "/\\?([0-9]+)|:([a-zA-Z0-9_]+):/",
			matches = null, setOrder = 2;

		if preg_match_all(bindPattern, sql, matches, setOrder) {
			for placeMatch in matches {

				if !fetch value, params[placeMatch[1]] {
					if isset placeMatch[2] {
						if !fetch value, params[placeMatch[2]] {
							throw new Exception("Matched parameter wasn't found in parameters list");
						}
					} else {
						throw new Exception("Matched parameter wasn't found in parameters list");
					}
				}

				let placeHolders[] = value;
			}

			let boundSql = preg_replace(bindPattern, "?", sql);
		} else {
			let boundSql = sql;
		}

		return [
			"sql"    : boundSql,
			"params" : placeHolders
		];
	}

	/**
	 * Returns the insert id for the auto_increment/serial column inserted in the latest executed SQL statement
	 *
	 *<code>
	 * // Inserting a new robot
	 * $success = $connection->insert(
	 *     "robots",
	 *     [
	 *         "Astro Boy",
	 *         1952,
	 *     ],
	 *     [
	 *         "name",
	 *         "year",
	 *     ]
	 * );
	 *
	 * // Getting the generated id
	 * $id = $connection->lastInsertId();
	 *</code>
	 *
	 * @param string sequenceName
	 * @return int|boolean
	 */
	public function lastInsertId(sequenceName = null) -> int | boolean
	{
		var pdo;
		let pdo = this->_pdo;
		if typeof pdo != "object" {
			return false;
		}
		return pdo->lastInsertId(sequenceName);
	}

	/**
	 * Starts a transaction in the connection
	 */
	public function begin(boolean nesting = true) -> boolean
	{
		var pdo, transactionLevel, eventsManager, savepointName;

		let pdo = this->_pdo;
		if typeof pdo != "object" {
			return false;
		}

		/**
		 * Increase the transaction nesting level
		 */
		let this->_transactionLevel++;

		/**
		 * Check the transaction nesting level
		 */
		let transactionLevel = (int) this->_transactionLevel;

		if transactionLevel == 1 {

			/**
			 * Notify the events manager about the started transaction
			 */
			let eventsManager = <ManagerInterface> this->_eventsManager;
			if typeof eventsManager == "object" {
				eventsManager->fire("db:beginTransaction", this);
			}

			return pdo->beginTransaction();
		} else {

			/**
			 * Check if the current database system supports nested transactions
			 */
			if transactionLevel && nesting && this->isNestedTransactionsWithSavepoints() {

				let eventsManager = <ManagerInterface> this->_eventsManager,
					savepointName = this->getNestedTransactionSavepointName();

				/**
				 * Notify the events manager about the created savepoint
				 */
				if typeof eventsManager == "object" {
					eventsManager->fire("db:createSavepoint", this, savepointName);
				}

				return this->createSavepoint(savepointName);
			}

		}

		return false;
	}

	/**
	 * Rollbacks the active transaction in the connection
	 */
	public function rollback(boolean nesting = true) -> boolean
	{
		var pdo, transactionLevel, eventsManager, savepointName;

		let pdo = this->_pdo;
		if typeof pdo != "object" {
			return false;
		}

		/**
		 * Check the transaction nesting level
		 */
		let transactionLevel = (int) this->_transactionLevel;
		if !transactionLevel {
			throw new Exception("There is no active transaction");
		}

		if transactionLevel == 1 {

			/**
			 * Notify the events manager about the rollbacked transaction
			 */
			let eventsManager = <ManagerInterface> this->_eventsManager;
			if typeof eventsManager == "object" {
				eventsManager->fire("db:rollbackTransaction", this);
			}

			/**
			 * Reduce the transaction nesting level
			 */
			let this->_transactionLevel--;

			return pdo->rollback();

		} else {

			/**
			 * Check if the current database system supports nested transactions
			 */
			if transactionLevel && nesting && this->isNestedTransactionsWithSavepoints() {

				let savepointName = this->getNestedTransactionSavepointName();

				/**
				 * Notify the events manager about the rolled back savepoint
				 */
				let eventsManager = <ManagerInterface> this->_eventsManager;
				if typeof eventsManager == "object" {
					eventsManager->fire("db:rollbackSavepoint", this, savepointName);
				}

				/**
				 * Reduce the transaction nesting level
				 */
				let this->_transactionLevel--;

				return this->rollbackSavepoint(savepointName);
			}
		}

		/**
		 * Reduce the transaction nesting level
		 */
		if transactionLevel > 0 {
			let this->_transactionLevel--;
		}

		return false;
	}

	/**
	 * Commits the active transaction in the connection
	 */
	public function commit(boolean nesting = true) -> boolean
	{
		var pdo, transactionLevel, eventsManager, savepointName;

		let pdo = this->_pdo;
		if typeof pdo != "object" {
			return false;
		}

		/**
		 * Check the transaction nesting level
		 */
		let transactionLevel = (int) this->_transactionLevel;
		if !transactionLevel {
			throw new Exception("There is no active transaction");
		}

		if transactionLevel == 1 {

			/**
			 * Notify the events manager about the committed transaction
			 */
			let eventsManager = <ManagerInterface> this->_eventsManager;
			if typeof eventsManager == "object" {
				eventsManager->fire("db:commitTransaction", this);
			}

			/**
			 * Reduce the transaction nesting level
			 */
			let this->_transactionLevel--;

			return pdo->commit();
		} else {

			/**
			 * Check if the current database system supports nested transactions
			 */
			if transactionLevel && nesting && this->isNestedTransactionsWithSavepoints() {

				/**
				 * Notify the events manager about the committed savepoint
				 */
				let eventsManager = <ManagerInterface> this->_eventsManager,
					savepointName = this->getNestedTransactionSavepointName();
				if typeof eventsManager == "object" {
					eventsManager->fire("db:releaseSavepoint", this, savepointName);
				}

				/**
				 * Reduce the transaction nesting level
				 */
				let this->_transactionLevel--;

				return this->releaseSavepoint(savepointName);
			}

		}

		/**
		 * Reduce the transaction nesting level
		 */
		if transactionLevel > 0 {
			let this->_transactionLevel--;
		}

		return false;
	}

	/**
	 * Returns the current transaction nesting level
	 */
	public function getTransactionLevel() -> int
	{
		return this->_transactionLevel;
	}

	/**
	 * Checks whether the connection is under a transaction
	 *
	 *<code>
	 * $connection->begin();
	 *
	 * // true
	 * var_dump(
	 *     $connection->isUnderTransaction()
	 * );
	 *</code>
	 */
	public function isUnderTransaction() -> boolean
	{
		var pdo;
		let pdo = this->_pdo;
		if typeof pdo == "object" {
			return pdo->inTransaction();
		}
		return false;
	}

	/**
	 * Return internal PDO handler
	 */
	public function getInternalHandler() -> <\Pdo>
	{
		return this->_pdo;
	}

	/**
	 * Return the error info, if any
	 *
	 * @return array
	 */
	public function getErrorInfo()
	{
		return this->_pdo->errorInfo();
	}
}
