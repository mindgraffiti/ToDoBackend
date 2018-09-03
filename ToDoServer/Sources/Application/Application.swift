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

    private var todoStore: [ToDo] = []
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
        execute {
            todoStore.append(todo)
        }
        completion(todo, nil)
    }

    /// Careful! The DELETE request deletes all items.
    ///
    func deleteAllHandler(completion: @escaping (RequestError?) -> Void) {
        execute {
            todoStore = []
        }
        completion(nil)
    }

    /// Deletes a single to-do item by ID.
    ///
    func deleteOneHandler(id: Int, completion: @escaping (RequestError?) -> Void) {
        guard let index = todoStore.index(where: { $0.id == id }) else {
            return completion(.notFound)
        }
        execute {
            todoStore.remove(at: index)
        }
        completion(nil)
    }

    /// Gets all to-do list items.
    ///
    func getAllHandler(completion: @escaping ([ToDo]?, RequestError?) -> Void) {
        completion(todoStore, nil)
    }

    /// Gets a single to-do item by ID.
    ///
    func getOneHandler(id: Int, completion: @escaping (ToDo?, RequestError?) -> Void) {
        guard let todo = todoStore.first(where: { $0.id == id }) else {
            return completion(nil, .notFound)
        }
        completion(todo, nil)
    }

    /// Updates all fields for a single to-do item.
    ///
    func updateHandler(id: Int, new: ToDo, completion: @escaping (ToDo?, RequestError?) -> Void) {
        guard let index = todoStore.index(where: { $0.id == id }) else {
            return completion(nil, .notFound)
        }

        var current = todoStore[index]
        current.user = new.user ?? current.user
        current.order = new.order ?? current.order
        current.title = new.title ?? current.title
        current.completed = new.completed ?? current.completed

        execute {
            todoStore[index] = current
        }
        completion(current, nil)
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
