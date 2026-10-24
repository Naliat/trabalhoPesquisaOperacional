using JuMP
using Gurobi
using LinearAlgebra

# Valida se a sequência de arcos forma um caminho hamiltoniano válido de s a t.
function validate_hamiltonian_path(n::Int, active_arcs::Vector{Tuple{Int,Int}}, s::Int, t::Int)
    if length(active_arcs) != n - 1
        return false
    end

    in_degree = zeros(Int, n)
    out_degree = zeros(Int, n)
    adj_map = Dict{Int, Int}()

    for (u, v) in active_arcs
        if u < 1 || u > n || v < 1 || v > n || u == v
            return false
        end
        out_degree[u] += 1
        in_degree[v] += 1
        adj_map[u] = v
    end

    if out_degree[s] != 1 || in_degree[s] != 0
        return false
    end
    
    if in_degree[t] != 1 || out_degree[t] != 0
        return false
    end

    for k in 1:n
        if k != s && k != t
            if out_degree[k] != 1 || in_degree[k] != 1
                return false
            end
        end
    end

    visited = Set{Int}([s])
    current = s
    while haskey(adj_map, current)
        next_node = adj_map[current]
        if in(next_node, visited)
            return false
        end
        push!(visited, next_node)
        current = next_node
    end

    return (current == t) && (length(visited) == n)
end

# Resolve o PCHM com formulação MTZ (relaxação linear ou modelo inteiro).
function solve_mphp_model(cost_matrix::Matrix{Float64}; is_integer::Bool=true, time_limit_sec::Real=180.0)
    n = size(cost_matrix, 1)
    s = 1
    t = n

    model = Model(Gurobi.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, time_limit_sec)

    set_attribute(model, "Presolve", 2)
    set_attribute(model, "Cuts", 2)
    
    if !is_integer
        @variable(model, 0.0 <= x[1:n, 1:n] <= 1.0)
        @variable(model, u[1:n] >= 0.0)
    else
        @variable(model, x[1:n, 1:n], Bin)
        @variable(model, u[1:n] >= 0, Int)
    end

    @objective(model, Min, sum(cost_matrix[i, j] * x[i, j] for i in 1:n, j in 1:n if i != j))

    for i in 1:n
        @constraint(model, x[i, i] == 0)
    end

    @constraint(model, sum(x[s, j] for j in 1:n if j != s) == 1)
    @constraint(model, sum(x[i, t] for i in 1:n if i != t) == 1)
    @constraint(model, sum(x[i, s] for i in 1:n if i != s) == 0)
    @constraint(model, sum(x[t, j] for j in 1:n if j != t) == 0)

    for k in 1:n
        if k != s && k != t
            @constraint(model, sum(x[i, k] for i in 1:n if i != k) == 1)
            @constraint(model, sum(x[k, j] for j in 1:n if j != k) == 1)
        end
    end

    @constraint(model, u[s] == 1)
    
    for i in 1:n
        if i != s
            @constraint(model, 2 <= u[i] <= n)
        end
    end

    for i in 1:n, j in 1:n
        if j != s && i != j
            @constraint(model, u[i] - u[j] + n * x[i, j] <= n - 1)
        end
    end

    execution_time = @elapsed optimize!(model)
    st = termination_status(model)
    has_solution = (result_count(model) > 0)
    cost = has_solution ? objective_value(model) : Inf

    solution_arcs = Tuple{Int, Int}[]
    if has_solution && is_integer
        for i in 1:n, j in 1:n
            if i != j && value(x[i, j]) > 0.5
                push!(solution_arcs, (i, j))
            end
        end
    end

    return (status = st, custo = cost, tempo = execution_time, arcos = solution_arcs)
end
