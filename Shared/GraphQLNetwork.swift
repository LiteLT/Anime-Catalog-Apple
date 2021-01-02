//
//  GraphQLNetwork.swift
//  Amincapp
//
//  Created by Kyle Erhabor on 9/4/20.
//

import Apollo
import Foundation

class GraphQLNetwork {
    static let shared: ApolloClient = {
        let store = ApolloStore()

        return ApolloClient(networkTransport: RequestChainNetworkTransport(
            interceptorProvider: GraphQLNetworkInterceptorProvider(
                store: store,
                client: URLSessionClient()
            ),
            endpointURL: URL(string: "https://graphql.anilist.co/")!
        ), store: store)
    }()
}

fileprivate struct GraphQLNetworkInterceptorProvider {
    private let store: ApolloStore
    private let client: URLSessionClient

    init(store: ApolloStore, client: URLSessionClient) {
        self.store = store
        self.client = client
    }
}

extension GraphQLNetworkInterceptorProvider: InterceptorProvider {
    func interceptors<Operation: GraphQLOperation>(for operation: Operation) -> [ApolloInterceptor] {
        return [
            MaxRetryInterceptor(maxRetriesAllowed: 1),
            AuthorizationHeaderAddingInterceptor(),
            NetworkFetchInterceptor(client: client),
            LegacyParsingInterceptor(cacheKeyForObject: store.cacheKeyForObject),
            ResponseCheckingInterceptor(),
            AutomaticPersistedQueryInterceptor(),
            LegacyCacheWriteInterceptor(store: store)
        ]
    }
}

fileprivate class AuthorizationHeaderAddingInterceptor: ApolloInterceptor {
    func interceptAsync<Operation: GraphQLOperation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) {
        if let tokens = UserDefaults.standard.stringArray(forKey: SettingsKeys.accessTokens), !tokens.isEmpty {
            let accountIndex = UserDefaults.standard.integer(forKey: SettingsKeys.accountIndex)

            request.addHeader(name: "Authorization", value: "Bearer \(tokens[accountIndex])")
        }

        chain.proceedAsync(request: request, response: response, completion: completion)
    }
}

fileprivate class ResponseCheckingInterceptor: ApolloInterceptor {
    func interceptAsync<Operation: GraphQLOperation>(
        chain: RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void
    ) {
        if response?.parsedResponse?.errors?.contains(where: { $0.message == "Invalid token" }) == true {
            // Tokens are long-lived, so they shouldn't expire unless the user has revoked access.
            //
            // It would be nice to call `CurrentUser.removeUser(:)`, but instances of the class only live in views.
            // Instead, we'll remove it from the UserDefaults settings.
            UserDefaults.standard.set(nil, forKey: SettingsKeys.accessTokens)
            chain.retry(request: request, completion: completion)

            return
        }

        chain.proceedAsync(request: request, response: response, completion: completion)
    }
}