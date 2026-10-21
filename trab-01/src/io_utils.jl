using Plots
using Random

"""
    read_tsplib_instance(file_path::String)

Interpreta cabeçalhos e quebras de linha de arquivos .atsp no padrão da TSPLIB.
"""
function read_tsplib_instance(file_path::String)
    lines = filter(l -> !isempty(strip(l)) && !startswith(strip(l), "#"), readlines(file_path))
    if isempty(lines) error("Arquivo completamente vazio.") end
    
    n = 0
    raw_values = Float64[]
    inside_weight_section = false
    
    for line in lines
        line_clean = strip(line)
        
        # Captura a dimensao tratando o separador de dois pontos com seguranca
        if startswith(uppercase(line_clean), "DIMENSION")
            parts = split(line_clean, ":")
            n = parse(Int, strip(parts[2]))
        elseif startswith(uppercase(line_clean), "EDGE_WEIGHT_SECTION")
            inside_weight_section = true
            continue
        elseif startswith(uppercase(line_clean), "EOF") || startswith(uppercase(line_clean), "TOUR_SECTION")
            break
        end
        
        if inside_weight_section
            for val in split(line_clean) 
                push!(raw_values, parse(Float64, val)) 
            end
        end
    end
    
    if n == 0 || isempty(raw_values)
        error("Formato invalido ou secao de pesos nao encontrada no arquivo .atsp.")
    end
    
    cost_matrix = zeros(Float64, n, n)
    idx = 1
    for i in 1:n, j in 1:n
        if idx <= length(raw_values)
            cost_matrix[i, j] = raw_values[idx]
            idx += 1
        end
    end
    return n, cost_matrix
end

"""
    generate_route_plot(n::Int, active_arcs::Vector{Tuple{Int,Int}}, instance_name::String, save_folder::String)

Plota o mapa disperso em 2D com degradê de cores sequencial baseado no progresso da rota.
"""
function generate_route_plot(n::Int, active_arcs::Vector{Tuple{Int,Int}}, instance_name::String, save_folder::String)
    if !ispath(save_folder) mkdir(save_folder) end
    if isempty(active_arcs) return end 

    gr()

    # Semente estavel baseada no nome do arquivo para manter os nos fixos no mapa
    Random.seed!(abs(hash(instance_name) % 10000))
    x_nodes = rand(5.0:95.0, n)
    y_nodes = rand(5.0:95.0, n)
    
    p = plot(
        title = "Mapa Logistico Rastreavel (N = $n)\nInstancia: $instance_name",
        titlefont = font(12, :bold),
        size = (1100, 850),
        grid = true,
        gridalpha = 0.1,
        background_color = :white
    )
    
    adj_dict = Dict(i => j for (i, j) in active_arcs)
    route_sequence = Int[]
    current = 1
    push!(route_sequence, current)
    while haskey(adj_dict, current) && length(route_sequence) < n
        current = adj_dict[current]
        push!(route_sequence, current)
    end

    colors_gradient = cgrad(:viridis, max(1, length(route_sequence)-1), categorical=true)
    if length(route_sequence) > 1
        for idx in 1:(length(route_sequence)-1)
            i, j = route_sequence[idx], route_sequence[idx+1]
            plot!([x_nodes[i], x_nodes[j]], [y_nodes[i], y_nodes[j]], color=colors_gradient[idx], linewidth=2.5, alpha=0.9, label="")
            scatter!([(x_nodes[i]+x_nodes[j])/2], [(y_nodes[i]+y_nodes[j])/2], marker=:utriangle, markersize=5, color=colors_gradient[idx], markerstrokewidth=0, label="")
        end
    end
    
    scatter!(x_nodes, y_nodes, markersize=6, color=:lightgrey, label="Cidades")
    scatter!([x_nodes[1]], [y_nodes[1]], color=:lime, markersize=14, marker=:square, label="INICIO (Cidade 1)")
    scatter!([x_nodes[n]], [y_nodes[n]], color=:crimson, markersize=14, marker=:star8, label="FIM (Cidade $n)")
    
    if n <= 60
        for i in 1:n
            annotate!(x_nodes[i], y_nodes[i] + 2.5, text(string(i), :black, :center, :bold, 6))
        end
    end
    
    image_name = replace(instance_name, r"\.atsp$" => ".png")
    savefig(p, joinpath(save_folder, endswith(image_name, ".png") ? image_name : image_name * ".png"))
    println("     [INFO] Grafico de rota gerado: ", joinpath(save_folder, image_name))
end
