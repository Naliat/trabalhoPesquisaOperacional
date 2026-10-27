ENV["GKSwstype"] = "100"

using Plots
using Random
using Printf

include("grasp_solver.jl")

# Carrega e monta a matriz de custos de arquivos .atsp.
function load_atsp_instance(path::String)
    if !isfile(path) || filesize(path) == 0
        error("Arquivo vazio ou inexistente.")
    end
    lines = readlines(path)
    n = 0
    raw_values = Float64[]
    in_weight_section = false
    
    for line in lines
        clean_line = strip(line)
        if isempty(clean_line) continue end
        if startswith(uppercase(clean_line), "DIMENSION")
            parts = split(clean_line, ":")
            n = parse(Int, strip(parts[end]))
        elseif startswith(uppercase(clean_line), "EDGE_WEIGHT_SECTION")
            in_weight_section = true
            continue
        elseif startswith(uppercase(clean_line), "EOF") || startswith(uppercase(clean_line), "TOUR_SECTION")
            break
        end
        
        if in_weight_section
            for val in split(clean_line)
                push!(raw_values, parse(Float64, val))
            end
        end
    end
    
    C = zeros(Float64, n, n)
    idx = 1
    for i in 1:n, j in 1:n
        C[i, j] = raw_values[idx]
        idx += 1
    end
    return n, C
end

# Gera e salva no disco o gráfico da rota percorrida.
function generate_path_plot(n::Int, route::Vector{Int}, instance_name::String, output_folder::String)
    if isempty(route) return end
    if !isdir(output_folder) mkpath(output_folder) end
    gr()
    
    seed = hash(instance_name) % 10000
    Random.seed!(abs(seed))
    x_nodes = rand(5.0:95.0, n)
    y_nodes = rand(5.0:95.0, n)
    
    p = plot(
        title = "PCHM GRASP - $instance_name (n = $n)",
        titlefont = font(11, :bold),
        size = (1000, 800),
        grid = true,
        gridalpha = 0.15,
        background_color = :white,
        legend = :topright
    )
    
    for idx in 1:(length(route) - 1)
        u = route[idx]
        v = route[idx + 1]
        plot!([x_nodes[u], x_nodes[v]], [y_nodes[u], y_nodes[v]], color = :blue, linewidth = 2.0, alpha = 0.85, label = "")
        mx = (x_nodes[u] + x_nodes[v]) / 2.0
        my = (y_nodes[u] + y_nodes[v]) / 2.0
        scatter!([mx], [my], marker = :utriangle, markersize = 4, color = :blue, label = "")
    end
    
    scatter!(x_nodes, y_nodes, markersize = 6, color = :lightgrey, markerstrokecolor = :black, label = "Vertices")
    scatter!([x_nodes[1]], [y_nodes[1]], color = :lime, markersize = 12, marker = :square, label = "Origem (s=1)")
    scatter!([x_nodes[n]], [y_nodes[n]], color = :crimson, markersize = 12, marker = :star8, label = "Destino (t=$n)")
    
    if n <= 60
        for i in 1:n annotate!(x_nodes[i], y_nodes[i] + 2.0, text(string(i), :black, :center, :bold, 6)) end
    end
    
    output_png = replace(instance_name, r"\.(atsp|txt)$" => ".png")
    savefig(p, joinpath(output_folder, output_png))
end

# Executa a Heurística Inicial (Ativ. 1) e a Meta-heurística GRASP (Ativ. 2) em lote.
function execute_batch_processing()
    target_dir = "instancias-professor"
    if !ispath(target_dir) return end

    atsp_files = sort(filter(f -> endswith(f, ".atsp"), readdir(target_dir)))
    if !ispath("data") mkpath("data") end
    csv_path = joinpath("data", "resultado_otimizacao.csv")

    println(@sprintf("%-15s | %-3s | %10s | %8s | %10s | %8s | %9s | %-6s", 
                     "Instancia", "n", "Z_Inicial", "T_Init", "Z_GRASP", "T_GRASP", "Melhoria", "Valido"))
    println(repeat("-", 88))

    open(csv_path, "w") do f_csv
        write(f_csv, "Instancia;N;Z_Inicial;Tempo_Inicial_s;Z_GRASP;Tempo_GRASP_s;Melhoria_Percentual;Caminho_Valido;Rota_Percorrida\n")

        for file in atsp_files
            full_path = joinpath(target_dir, file)
            n, costs = load_atsp_instance(full_path)
            
            # 1. Heurística Inicial da Seção 2 (Atividade 1)
            t_start_init = time()
            initial_route = run_initial_heuristic(n, costs)
            t_end_init = time()
            z_init = calculate_route_cost(initial_route, costs)
            time_init = t_end_init - t_start_init
            
            # 2. Meta-heurística GRASP Completa (Atividade 2)
            Random.seed!(42)
            t_start_grasp = time()
            best_route, best_cost_global = run_grasp_metaheuristic(n, costs, 1000, 0.15)
            t_end_grasp = time()
            time_grasp = t_end_grasp - t_start_grasp
            
            generate_path_plot(n, best_route, file, "data/plots")
            
            melhoria = z_init > 0 ? ((z_init - best_cost_global) / z_init) * 100.0 : 0.0
            is_valid = (length(best_route) == n && length(unique(best_route)) == n && best_route[1] == 1 && best_route[end] == n)
            formatted_vector = "[" * join(best_route, ", ") * "]"

            println(@sprintf("%-15s | %-3d | %10.2f | %7.4fs | %10.2f | %7.4fs | %8.2f%% | %-6s",
                             file, n, z_init, time_init, best_cost_global, time_grasp, melhoria, string(is_valid)))

            write(f_csv, "$file;$n;$(round(z_init, digits=2));$(round(time_init, digits=6));$(round(best_cost_global, digits=2));$(round(time_grasp, digits=4));$(round(melhoria, digits=2));$is_valid;$formatted_vector\n")
        end
    end

    println(repeat("-", 88))
    println("Processamento concluido! Resultados salvos em data/resultado_otimizacao.csv")
end

execute_batch_processing()
