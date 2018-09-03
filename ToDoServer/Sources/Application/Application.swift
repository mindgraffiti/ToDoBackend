import Dispatch
import Foundation
import Kitura
import LoggerAPI
import Configuration
import CloudEnvironment
import KituraContracts
import Health
import KituraOpenAPI
import KituraCORS
import SwiftKueryORM
import SwiftKueryPostgreSQL

public let projectPath = ConfigurationManager.BasePath.project.path
public let health = Health()

public class App {
    let router = Router()
    let cloudEnv = CloudEnv()

    private var nextId: Int = 0
    private let workerQueue = DispatchQueue(label: "worker")

    public init() throws {
        // Run the metrics initializer
        initializeMetrics(router: router)
    }

    func postInit() throws {
        let options = Options(allowedOrigin: .all)
        let cors = CORS(options: options)

        // API request handlers
        router.all("/*", middleware: cors)

        router.post("/", handler: storeHandler)

        router.delete("/", handler: deleteAllHandler)
        router.delete("/", handler: deleteOneHandler)

        router.get("/", handler: getAllHandler)
        router.get("/", handler: getOneHandler)

        router.patch("/", handler: updateHandler)

        // Endpoints
        initializeHealthRoutes(app: self)
        KituraOpenAPI.addEndpoints(to: router)

        // Persistence
        Persistence.setUp()
        do {
            try ToDo.createTableSync()
        } catch let error {
            print("Table already exists. Error: \(String(describing: error))")
        }
    }

    public func run() throws {
        try postInit()
        Kitura.addHTTPServer(onPort: cloudEnv.port, with: router)
        Kitura.run()
    }

    func execute(_ block: (() -> Void)) {
        workerQueue.sync {
            block()
        }
    }

    // MARK: - API GET, POST, UPDATE, DELETE Handlers
    //

    /// The storeHandler takes care of all general POST requests
    ///
    func storeHandler(todo: ToDo, completion: @escaping (ToDo?, RequestError?) -> Void ) {
        var todo = todo
        if todo.completed == nil {
            todo.completed = false
        }
        todo.id = nextId
        todo.url = "http://localhost:8080/\(nextId)"
        nextId += 1
        todo.save(completion)
    }

    /// Careful! The DELETE request deletes all items.
    ///
    func deleteAllHandler(completion: @escaping (RequestError?) -> Void) {
        ToDo.deleteAll(completion)
    }

    /// Deletes a single to-do item by ID.
    ///
    func deleteOneHandler(id: Int, completion: @escaping (RequestError?) -> Void) {
        ToDo.delete(id: id, completion)
    }

    /// Gets all to-do list items.
    ///
    func getAllHandler(completion: @escaping ([ToDo]?, RequestError?) -> Void) {
        ToDo.findAll(completion)
    }

    /// Gets a single to-do item by ID.
    ///
    func getOneHandler(id: Int, completion: @escaping (ToDo?, RequestError?) -> Void) {
        ToDo.find(id: id, completion)
    }

    /// Updates all fields for a single to-do item.
    ///
    func updateHandler(id: Int, new: ToDo, completion: @escaping (ToDo?, RequestError?) -> Void) {
        ToDo.find(id: id) { (preExistingToDo, error) in
            if error != nil {
                return completion(nil, .notFound)
            }

            guard var oldToDo = preExistingToDo else {
                return completion(nil, .notFound)
            }

            guard let id = oldToDo.id else {
                return completion(nil, .internalServerError)
            }

            oldToDo.user = new.user ?? oldToDo.user
            oldToDo.order = new.order ?? oldToDo.order
            oldToDo.title = new.title ?? oldToDo.title
            oldToDo.completed = new.completed ?? oldToDo.completed

            oldToDo.update(id: id, completion)
        }
    }
}

extension ToDo: Model {
    
}

class Persistence {
    static func setUp() {
        let pool = PostgreSQLConnection.createPool(host: "localhost", port: 5432, options: [.databaseName("tododb")], poolOptions: ConnectionPoolOptions(initialCapacity: 10, maxCapacity: 50, timeout: 10000))
        Database.default = Database(pool)
    }
}
