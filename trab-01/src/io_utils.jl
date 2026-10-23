using Plots
using Random

"""
    load_txt_instance(path::String)

Lê e valida o formato das instâncias do tipo TXT comum.
"""
function load_txt_instance(path::String)
    if !isfile(path) || filesize(path) == 0
        error("Arquivo vazio ou inexistente.")
    end
    # Filtra linhas vazias removendo espacos em branco nas bordas
    lines = filter(!isempty, strip.(readlines(path)))
    if isempty(lines)
        error("Arquivo sem conteudo legivel.")
    end
    
    # Extrai a dimensao n contida na primeira linha
    n = tryparse(Int, lines[1])
    if n === nothing || n < 2
        error("Numero de vertices invalido: $(lines[1])")
    end
    if length(lines) < n + 1
        error("Linhas insuficientes: esperado $(n + 1), lido $(length(lines))")
    end
    
    # Preenche a matriz bidimensional linha por linha
    C = zeros(Float64, n, n)
    for i in 1:n
        tokens = split(lines[i + 1])
        if length(tokens) != n
            error("Linha $i tem $(length(tokens)) colunas (esperado $n)")
        end
        for j in 1:n
            val = tryparse(Float64, tokens[j])
            if val === nothing
                error("Caractere invalido em ($i, $j): $(tokens[j])")
            end
            if val < 0.0
                error("Custo negativo em ($i, $j): $val")
            end
            C[i, j] = val
        end
    end
    return n, C
end

"""
    load_atsp_instance(path::String)

Lê cabeçalhos estruturados e corrige as quebras de linha dos arquivos .atsp da TSPLIB.
"""
function load_atsp_instance(path::String)
    if !isfile(path) || filesize(path) == 0
        error("Arquivo vazio ou inexistente.")
    end
    lines = readlines(path)
    n = 0
    raw_values = Float64[]
    in_weight_section = false
    
    # Varre a estrutura do arquivo procurando marcas do cabecalho TSPLIB
    for line in lines
        clean_line = strip(line)
        if isempty(clean_line)
            continue
        end
        # Extrai o valor numerico da dimensao n contida apos o delimitador de dois pontos
        if startswith(uppercase(clean_line), "DIMENSION")
            parts = split(clean_line, ":")
            n = parse(Int, strip(parts[end]))
        # Identifica a flag de secao de custos para iniciar a coleta sequencial
        elseif startswith(uppercase(clean_line), "EDGE_WEIGHT_SECTION")
            in_weight_section = true
            continue
        # Interrompe a leitura caso encontre o finalizador oficial do formato
        elseif startswith(uppercase(clean_line), "EOF") || startswith(uppercase(clean_line), "TOUR_SECTION")
            break
        end
        
        # Junta os dados numericos em um array de fluxo continuo contornando quebras falsas de linha
        if in_weight_section
            line_data = split(clean_line)
            for val in line_data
                push!(raw_values, parse(Float64, val))
            end
        end
    end
    
    if n == 0 || length(raw_values) < n * n
        error("Formato atsp invalido ou pesos insuficientes.")
    end
    
    # Reconstroi o bloco quadrado n x n utilizando os valores lineares processados
    C = zeros(Float64, n, n)
    idx = 1
    for i in 1:n, j in 1:n
        C[i, j] = raw_values[idx]
        idx += 1
    end
    return n, C
end

"""
    generate_path_plot(n::Int, arcs::Vector{Tuple{Int, Int}}, instance_name::String, output_folder::String)

Gera o mapa plano cartesiano contínuo em degradê para cada resultado viável encontrado.
"""
function generate_path_plot(n::Int, arcs::Vector{Tuple{Int, Int}}, instance_name::String, output_folder::String)
    if isempty(arcs) return end
    if !isdir(output_folder) mkpath(output_folder) end
    gr()
    
    # Fixa uma semente estavel gerada por hash para travar a posicao x,y das cidades no canvas
    seed = hash(instance_name) % 10000
    Random.seed!(abs(seed))
    x_nodes = rand(5.0:95.0, n)
    y_nodes = rand(5.0:95.0, n)
    
    # Inicia a tela de desenho bidimensional limpa com fundo branco
    p = plot(
        title = "PCHM MTZ - \$instance_name (n = \$n)",
        titlefont = font(11, :bold),
        size = (1000, 800),
        grid = true,
        gridalpha = 0.15,
        background_color = :white,
        legend = :topright
    )
    
    # Ordena a sequencia dos nos com base no dicionario de conexao para criar o efeito visual de gradiente
    adj = Dict(u => v for (u, v) in arcs)
    sequence = Int[]
    current = 1
    push!(sequence, current)
    while haskey(adj, current) && length(sequence) < n
        current = adj[current]
        push!(sequence, current)
    end
    
    # Gera a escala de cores continua (viridis) proporcional ao tamanho do percurso sequencial
    gradient = cgrad(:viridis, max(1, length(sequence) - 1), categorical=true)
    if length(sequence) > 1
        for idx in 1:(length(sequence) - 1)
            u = sequence[idx]
            v = sequence[idx + 1]
            # Desenha o segmento de linha com a respectiva cor do degradê
            plot!([x_nodes[u], x_nodes[v]], [y_nodes[u], y_nodes[v]], color = gradient[idx], linewidth = 2.0, alpha = 0.85, label = "")
            
            # Insere marcadores de direcao triangulares posicionados no ponto medio do segmento
            mx = (x_nodes[u] + x_nodes[v]) / 2.0
            my = (y_nodes[u] + y_nodes[v]) / 2.0
            scatter!([mx], [my], marker = :utriangle, markersize = 4, color = gradient[idx], markerstrokewidth = 0, label = "")
        end
    end
    
    # Plota a dispersao das cidades e destaca com formatos chamativos a Origem (1) e o Destino (N)
    scatter!(x_nodes, y_nodes, markersize = (n > 50 ? 5 : 7), color = :lightgrey, markerstrokecolor = :black, markerstrokewidth = 0.5, label = "Vertices")
    scatter!([x_nodes[1]], [y_nodes[1]], color = :lime, markersize = 12, marker = :square, label = "Origem (s=1)")
    scatter!([x_nodes[n]], [y_nodes[n]], color = :crimson, markersize = 12, marker = :star8, label = "Destino (t=\$n)")
    
    # Insere as anotacoes numericas se a dimensao nao poluir a leitura do grafico
    if n <= 60
        for i in 1:n annotate!(x_nodes[i], y_nodes[i] + 2.0, text(string(i), :black, :center, :bold, 6)) end
    end
    
    # Ajusta o sufixo da imagem para gerar e salvar o arquivo png fisico no disco do Linux
    output_png = replace(instance_name, r"\.(txt|atsp)$" => ".png")
    savefig(p, joinpath(output_folder, output_png))
end
