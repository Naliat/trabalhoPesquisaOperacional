include("ds_union_find.jl")

# Calcula o custo total de uma sequência de nós.
function calculate_route_cost(route::Vector{Int}, costs::Matrix{Float64})
    cost = 0.0
    for i in 1:(length(route) - 1)
        cost += costs[route[i], route[i+1]]
    end
    return cost
end

# Heurística Inicial (Seção 2 / Atividade 1): Vizinho Mais Próximo de s=1 até t=n.
function run_initial_heuristic(n::Int, costs::Matrix{Float64})
    visited = zeros(Bool, n)
    route = Int[]
    current = 1
    push!(route, current)
    visited[current] = true
    
    for _ in 1:(n - 2)
        best_neighbor = -1
        min_val = Inf
        for j in 1:(n - 1)
            if !visited[j] && costs[current, j] < min_val && current != j
                min_val = costs[current, j]
                best_neighbor = j
            end
        end
        if best_neighbor == -1 break end
        push!(route, best_neighbor)
        visited[best_neighbor] = true
        current = best_neighbor
    end
    
    push!(route, n) 
    return route
end

# Fase construtiva semi-gulosa do GRASP usando Lista Restrita de Candidatos (RCL).
function grasp_construction(n::Int, costs::Matrix{Float64}, alpha::Float64)
    uf = new_union_find(n)
    visited = zeros(Bool, n)
    route = Int[]
    current = 1
    push!(route, current)
    visited[current] = true
    
    for _ in 1:(n - 2)
        candidates = Tuple{Int, Float64}[]
        for j in 1:(n - 1)
            if !visited[j] && current != j
                if find_representative!(uf, current) != find_representative!(uf, j)
                    push!(candidates, (j, costs[current, j]))
                end
            end
        end
        
        if isempty(candidates) break end
        
        c_min = minimum(c -> c[2], candidates)
        c_max = maximum(c -> c[2], candidates)
        threshold = c_min + alpha * (c_max - c_min)
        
        rcl = filter(c -> c[2] <= threshold, candidates)
        chosen = rand(rcl)
        next_node = chosen[1]
        
        push!(route, next_node)
        union_sets!(uf, current, next_node)
        visited[next_node] = true
        current = next_node
    end
    
    push!(route, n)
    return route
end

# Refina a rota usando busca local por realocação de nós intermediários (Or-Opt).
function grasp_local_search!(route::Vector{Int}, costs::Matrix{Float64}, n::Int)
    improved = true
    best_cost = calculate_route_cost(route, costs)
    
    while improved
        improved = false
        for i in 2:(n - 1)
            node = route[i]
            temp_route = deleteat!(copy(route), i)
            
            for j in 2:(n - 1)
                test_route = insert!(copy(temp_route), j, node)
                test_cost = calculate_route_cost(test_route, costs)
                
                if test_cost < best_cost
                    route .= test_route
                    best_cost = test_cost
                    improved = true
                    break
                end
            end
            if improved break end
        end
    end
    return best_cost
end

# Executa o laço iterativo do GRASP guardando a melhor rota global (Atividade 2).
function run_grasp_metaheuristic(n::Int, costs::Matrix{Float64}, max_iterations::Int, alpha::Float64)
    best_route = Int[]
    best_cost_global = Inf
    
    for iteration in 1:max_iterations
        candidate_route = grasp_construction(n, costs, alpha)
        if length(candidate_route) == n
            refined_cost = grasp_local_search!(candidate_route, costs, n)
            if refined_cost < best_cost_global
                best_cost_global = refined_cost
                best_route = candidate_route
            end
        end
    end
    return best_route, best_cost_global
end
