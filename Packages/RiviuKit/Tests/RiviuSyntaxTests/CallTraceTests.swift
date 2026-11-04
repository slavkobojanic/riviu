import Testing
@testable import RiviuSyntax

struct CallTraceTests {
    /// A small Java service: a gRPC handler calls a service through its interface, which uses a repository
    /// that reads a generated jOOQ record. A test and a TypeScript story use the same names.
    static let files: [(path: String, text: String)] = [
        ("shop/src/main/java/shop/E2eGrpcService.java", """
        package shop;

        public class E2eGrpcService {
            private final OrderService orderService;

            @Override
            public void completeCheckout(Request request, StreamObserver<Reply> observer) {
                var order = orderService.completeOrder(request.getOrderId());
                observer.onNext(Reply.of(order));
                observer.onCompleted();
            }
        }
        """),
        ("shop/src/main/java/shop/OrderService.java", """
        package shop;

        public interface OrderService {
            Order completeOrder(String id);
        }
        """),
        ("shop/src/main/java/shop/OrderServiceImpl.java", """
        package shop;

        public class OrderServiceImpl implements OrderService {
            private final OrderRepository repository;

            public Order completeOrder(String id) {
                var record = repository.findPending(id);
                record.getVendorId();
                return markPaid(record);
            }

            private Order markPaid(OrdersRecord record) {
                record.setStatus("paid");
                return new Order(record.getOrderId());
            }

            public String getName() {
                return "orders";
            }
        }
        """),
        ("shop/src/main/java/shop/OrderRepository.java", """
        package shop;

        public class OrderRepository {
            public OrdersRecord findPending(String id) {
                var query = dsl.selectFrom(ORDERS);
                return query.where(ORDERS.ID.eq(id)).fetchOne();
            }
        }
        """),
        ("shop/src/main/java/shop/generated/tables/records/OrdersRecord.java", """
        package shop.generated;

        public class OrdersRecord {
            public String getVendorId() {
                return (String) get(1);
            }

            public void setStatus(String value) {
                set(2, value);
            }
        }
        """),
        ("shop/src/test/java/shop/OrderServiceImplTest.java", """
        package shop;

        class OrderServiceImplTest {
            void completesTheOrder() {
                new OrderServiceImpl().completeOrder("1");
            }
        }
        """),
        ("web/src/form.stories.tsx", """
        export function completeOrder() {
            return markPaid()
        }
        """),
    ]

    @Test func tracesFromTheHandlerThroughTheImplementation() async {
        let index = await SymbolIndex.build(files: Self.files)
        let tracer = CallTracer(index: index, changedLines: ["shop/src/main/java/shop/OrderServiceImpl.java": [6]])
        // Line 6 of OrderServiceImpl: `var record = repository.findPending(id);`
        let trace = tracer.trace(path: "shop/src/main/java/shop/OrderServiceImpl.java", lines: 6...6)
        let names = trace?.steps.map(\.function.name)
        #expect(names == ["completeCheckout", "completeOrder", "findPending"])
        #expect(trace?.focusIndex == 1)
        #expect(trace?.steps.first?.callLine == 7)
        #expect(trace?.steps[1].callLine == 6)
        #expect(trace?.steps.last?.callLine == nil)
    }

    @Test func skipsGettersGeneratedCodeAndOtherLanguages() async {
        let index = await SymbolIndex.build(files: Self.files)
        let tracer = CallTracer(index: index, changedLines: [:])
        // Selecting the `return markPaid(record)` line follows markPaid, not the record's getters.
        let trace = tracer.trace(path: "shop/src/main/java/shop/OrderServiceImpl.java", lines: 8...8)
        let paths = trace?.steps.map(\.function.path) ?? []
        #expect(trace?.steps.map(\.function.name) == ["completeCheckout", "completeOrder", "markPaid"])
        #expect(!paths.contains { $0.contains("generated") || $0.contains("stories") || $0.contains("Test") })
    }

    @Test func followsAnInterfaceCallToItsImplementation() async {
        let index = await SymbolIndex.build(files: Self.files)
        let tracer = CallTracer(index: index, changedLines: [:])
        // Line 7 of the handler calls orderService.completeOrder, declared on the interface.
        let trace = tracer.trace(path: "shop/src/main/java/shop/E2eGrpcService.java", lines: 7...7)
        #expect(trace?.focusIndex == 0)
        #expect(trace?.steps.dropFirst().first?.function.path == "shop/src/main/java/shop/OrderServiceImpl.java")
    }

    @Test func linesOutsideAFunctionUseTheNearestOne() async {
        let index = await SymbolIndex.build(files: Self.files)
        let tracer = CallTracer(index: index, changedLines: [:])
        // Line 3 is the repository field, between the class line and completeOrder.
        let trace = tracer.trace(path: "shop/src/main/java/shop/OrderServiceImpl.java", lines: 3...3)
        #expect(trace?.steps[trace?.focusIndex ?? 0].function.name == "completeOrder")
    }

    @Test func recognizesTestsAndGeneratedPaths() {
        #expect(CallTracer.isTestOrGeneratedPath("web/src/form.stories.tsx"))
        #expect(CallTracer.isTestOrGeneratedPath("shop/src/test/java/OrderTest.java"))
        #expect(CallTracer.isTestOrGeneratedPath("shop/src/main/java/generated/OrdersRecord.java"))
        #expect(CallTracer.isTestOrGeneratedPath("shop/OrderServiceIT.java"))
        #expect(!CallTracer.isTestOrGeneratedPath("shop/src/main/java/shop/E2eGrpcService.java"))
        #expect(!CallTracer.isTestOrGeneratedPath("shop/src/main/java/shop/Latest.java"))
        #expect(!CallTracer.isTestOrGeneratedPath("shop/AUDIT.java"))
    }

    @Test func stopsAtCycles() async {
        let swift = """
        func ping() {
            pong()
        }

        func pong() {
            ping()
        }
        """
        let index = await SymbolIndex.build(files: [("Loop.swift", swift)])
        let trace = CallTracer(index: index, changedLines: [:]).trace(path: "Loop.swift", lines: 1...1)
        #expect(trace?.steps.map(\.function.name) == ["pong", "ping"])
    }
}
