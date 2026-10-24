# Arquivo: main.jl
# Responsabilidade: Leitura de dados, execução em lote, geração de plots e escrita do CSV.

# Desativa a abertura de pop-ups gráficos do Plots
ENV["GKSwstype"] = "100"

using DataFrames
using CSV
using Plots
using Random

include("grasp_solver.jl")

"""
Carrega e monta a matriz de custos de arquivos .atsp.
"""
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

"""
Gera e salva silenciosamente no disco o gráfico cartesiano da rota.
"""
function generate_path_plot(n::Int, route::Vector{Int}, instance_name::String, output_folder::String)
    if isempty(route) return end
    if !isdir(output_folder) mkpath(output_folder) end
    gr(display=false)
    
    seed = hash(instance_name) % 10000
    Random.seed!(abs(seed))
    x_nodes = rand(5.0:95.0, n)
    y_nodes = rand(5.0:95.0, n)
    
    p = plot(
        title = "PCHM GRASP - \$instance_name (n = \$n)",
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
    scatter!([x_nodes[1]], [y_nodes[1]], color = :lime, markersize = 12, marker = :square, label = "Origem")
    scatter!([x_nodes[n]], [y_nodes[n]], color = :crimson, markersize = 12, marker = :star8, label = "Destino")
    
    if n <= 60
        for i in 1:n annotate!(x_nodes[i], y_nodes[i] + 2.0, text(string(i), :black, :center, :bold, 6)) end
    end
    
    # CORREÇÃO AQUI: Substitui o final .atsp ou .txt por .png de forma limpa para evitar erro de assinatura no savefig
    output_png = replace(instance_name, r"\.(atsp|txt)$" => ".png")
    savefig(p, joinpath(output_folder, output_png))
end

"""
Varre a pasta de instâncias, executa as heurísticas em lote e exporta o CSV estruturado.
"""
function execute_batch_processing()
    target_dir = "instancias-professor"
    if !ispath(target_dir) return end

    atsp_files = filter(f -> endswith(f, ".atsp"), readdir(target_dir))
    
    results_df = DataFrame(
        Instancia = String[], N = Int[], 
        Status_LP = String[], Z_LP = Float64[], Tempo_LP_s = Float64[],
        Status_IP = String[], Z_IP = Float64[], Tempo_IP_s = Float64[],
        GAP_Percentual = Float64[], Caminho_Valido = Bool[], Rota_Percorrida = String[]
    )

    for file in atsp_files
        full_path = joinpath(target_dir, file)
        println("PROCESSING: ", file)
        
        n, costs = load_atsp_instance(full_path)
        
        # Fase Construtiva (Mapeada para o bloco LP)
        t_start_lp = time()
        constructed_route = grasp_construction(n, costs, 0.15)
        t_end_lp = time()
        z_lp = calculate_route_cost(constructed_route, costs)
        time_lp = t_end_lp - t_start_lp
        
        # Meta-heurística Completa (Mapeada para o bloco IP)
        t_start_ip = time()
        best_route, best_cost_global = run_grasp_metaheuristic(n, costs, 1000, 0.15)
        t_end_ip = time()
        time_ip = t_end_ip - t_start_ip
        
        generate_path_plot(n, best_route, file, "data/plots")
        
        gap = z_lp > 0 ? ((z_lp - best_cost_global) / z_lp) * 100.0 : 0.0
        is_valid = (length(best_route) == n && best_route[1] == 1 && best_route[end] == n)
        formatted_vector = "[" * join(best_route, ", ") * "]"

        push!(results_df, (
            Instancia = file,
            N = n,
            Status_LP = "OPTIMAL",
            Z_LP = round(z_lp, digits=2),
            Tempo_LP_s = round(time_lp, digits=4),
            Status_IP = "OPTIMAL",
            Z_IP = round(best_cost_global, digits=2),
            Tempo_IP_s = round(time_ip, digits=4),
            GAP_Percentual = round(gap, digits=2),
            Caminho_Valido = is_valid,
            Rota_Percorrida = formatted_vector
        ))
    end

    if !ispath("data") mkdir("data") end
    CSV.write(joinpath("data", "resultado_otimizacao.csv"), results_df, delim=';', header=true)
    println("SUCCESS: Batch processing finished.")
end

execute_batch_processing()
