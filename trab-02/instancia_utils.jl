# Funções e dados compartilhados entre os scripts do TP 02.

# Custo ótimo (ou melhor solução) e tempo do modelo PLI obtidos no Trabalho Prático 01.
const Z_PLI_TP1 = Dict(
    "br17.atsp" => 34.0, "ft53.atsp" => 6196.0, "ft70.atsp" => 37655.0,
    "ftv33.atsp" => 1275.0, "ftv35.atsp" => 1443.0, "ftv38.atsp" => 1511.0,
    "ftv44.atsp" => 1614.0, "ftv47.atsp" => 1754.0, "ftv55.atsp" => 1613.0,
    "ftv64.atsp" => 1840.0, "ftv70.atsp" => 1958.0, "p43.atsp" => 589.0,
    "ry48p.atsp" => 14070.0
)
const T_PLI_TP1 = Dict(
    "br17.atsp" => 0.32, "ft53.atsp" => 12.37, "ft70.atsp" => 2.06,
    "ftv33.atsp" => 0.47, "ftv35.atsp" => 0.35, "ftv38.atsp" => 0.39,
    "ftv44.atsp" => 0.95, "ftv47.atsp" => 1.43, "ftv55.atsp" => 2.06,
    "ftv64.atsp" => 6.11, "ftv70.atsp" => 6.89, "p43.atsp" => 180.04,
    "ry48p.atsp" => 1.70
)

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

# Lê os parâmetros (alpha, iterações) escolhidos pela calibração em data/parametros_escolhidos.txt.
function load_chosen_parameters(path::String = joinpath("data", "parametros_escolhidos.txt"))
    if !isfile(path)
        error("Execute primeiro: julia --project=. calibracao_grid.jl")
    end
    vals = Dict{String, String}()
    for line in readlines(path)
        kv = split(strip(line), "=")
        if length(kv) == 2 vals[kv[1]] = kv[2] end
    end
    return parse(Float64, vals["alpha"]), parse(Int, vals["iteracoes"])
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
